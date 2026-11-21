import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../../recording_io.dart' if (dart.library.js_interop) '../../recording_web.dart';
import 'shared.dart';

/// SCR-06 확인 카드. One delivery row of the period with its three records,
/// saved call memos, and the two-step answer flow: the card itself, then
/// "저장 전 확인" where the voice draft or typed text is edited before saving.
class TransactionScreen extends ConsumerStatefulWidget {
  const TransactionScreen(this.periodId, this.transactionId, {super.key});
  final String periodId;
  final String transactionId;

  @override
  ConsumerState<TransactionScreen> createState() => _TransactionScreenState();
}

enum _Step { card, review }

class _TransactionScreenState extends ConsumerState<TransactionScreen> {
  final _memo = TextEditingController();
  final _memoFocus = FocusNode();
  final _recorder = AudioRecorder();

  /// Request keys per action, kept while the same payload is retried.
  final _keys = <String, ({String signature, String key})>{};

  _Step _step = _Step.card;
  bool _voice = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _busy = false;

  @override
  void dispose() {
    _memo.dispose();
    _memoFocus.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  /// Same action with the same payload and revision reuses its key; any
  /// change of text or revision gets a fresh one.
  String _key(String action, Json body) {
    final signature = jsonEncode(body);
    final kept = _keys[action];
    if (kept != null && kept.signature == signature) return kept.key;
    final key = requestKey();
    _keys[action] = (signature: signature, key: key);
    return key;
  }

  /// Shared ending of every server mutation.
  void _settle(String action, Object? error) {
    if (error == null) {
      _keys.remove(action);
      refreshPeriod(ref, widget.periodId);
    } else if (error is ApiError && error.stale) {
      refreshPeriod(ref, widget.periodId);
    }
  }

  // ------------------------------------------------------------- answer flow

  void _openReview({required bool voice}) {
    setState(() {
      _step = _Step.review;
      _voice = voice;
    });
    if (!voice) _memoFocus.requestFocus();
  }

  void _cancelReview() {
    _memo.clear();
    setState(() {
      _step = _Step.card;
      _voice = false;
    });
  }

  /// After a failed recording the text on screen stays, and so does its
  /// source when it already was a voice draft.
  bool get _keepVoice => _step == _Step.review && _voice;

  Future<void> _toggleRecording() async {
    if (_recording) return _finishRecording();
    try {
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        notify(context, '마이크 권한이 꺼져 있습니다. 직접 입력으로 이어갑니다.');
        _openReview(voice: _keepVoice);
        return;
      }
      final opus = kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus);
      await _recorder.start(
          RecordConfig(encoder: opus ? AudioEncoder.opus : AudioEncoder.wav),
          path: await recordingPath(opus ? 'memo.webm' : 'memo.wav'));
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (!mounted) return;
      notify(context, '녹음을 시작하지 못했습니다. 직접 입력으로 이어갑니다.');
      _openReview(voice: _keepVoice);
    }
  }

  /// Stops the recorder, sends the audio for transcription and opens the
  /// draft for editing. Nothing is saved and no amount changes here (R04).
  Future<void> _finishRecording() async {
    setState(() {
      _recording = false;
      _transcribing = true;
      _busy = true;
    });
    try {
      final url = await _recorder.stop();
      if (url == null) throw StateError('no recording');
      // Web returns a blob URL, Android a temp file path.
      final (bytes: bytes, mime: mime) = await readRecording(url);
      if (bytes.isEmpty) throw StateError('empty recording');
      final extension = switch (mime) { 'audio/wav' => 'wav', 'audio/ogg' => 'ogg', _ => 'webm' };
      final response = await backend.upload('/api/transcriptions', bytes, 'memo.$extension', mime);
      if (!mounted) return;
      _memo.text = (response['draft_text'] ?? '').toString();
      _openReview(voice: true);
    } catch (_) {
      if (!mounted) return;
      notify(context, '받아쓰기를 하지 못했습니다. 직접 입력으로 이어갑니다.');
      _openReview(voice: _keepVoice);
    } finally {
      if (mounted) {
        setState(() {
          _transcribing = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveMemo(Object? revision) async {
    final text = _memo.text.trim();
    if (text.isEmpty) {
      notify(context, '저장할 내용을 입력하세요.');
      return;
    }
    final body = {
      'confirmed_text': text,
      'source_mode': _voice ? 'VOICE_MEMO' : 'TYPED_TEXT',
      'expected_revision': revision,
    };
    final error = await guarded(context, _setBusy, () async {
      await backend.post('/api/transactions/${part(widget.transactionId)}/memos',
          {...body, 'request_key': _key('memo', body)});
    });
    if (!mounted) return;
    _settle('memo', error);
    if (error != null) return;
    _cancelReview();
    notify(context, '답변을 저장했습니다. 이 거래만 다시 대조합니다.');
  }

  // ---------------------------------------------------------------- receipts

  Future<void> _editReceipt(Json tx, Object? revision) async {
    final target = _deliveryLineId(tx);
    if (target == null) {
      notify(context, '연결된 납품 명세 줄이 없어 수령 근거를 입력할 수 없습니다.');
      return;
    }
    final receipts = objects(tx['receipts']);
    final previous = receipts.isEmpty ? null : receipts.last;
    final input = await _receiptForm(context, previous, tx['unit']);
    if (input == null || !mounted) return;
    final qty = {'received_qty': input.qty, 'unit': input.unit};
    final body = {
      'kind': previous == null ? 'receipt_entry' : 'line_correction',
      'target_id': target,
      'expected_revision': revision,
      'evidence_text': input.reason,
      if (previous == null)
        ...qty
      else ...{
        'supersedes_receipt_id': previous['receipt_id'],
        'corrected_fields': qty,
      },
    };
    final error = await guarded(context, _setBusy, () async {
      await backend.post('${periodPath(widget.periodId)}/confirmations',
          {...body, 'request_key': _key('receipt', body)});
    });
    if (!mounted) return;
    _settle('receipt', error);
    if (error == null) notify(context, '수령 근거를 저장했습니다. 이 거래를 다시 대조합니다.');
  }

  static Object? _deliveryLineId(Json tx) {
    for (final r in objects(tx['evidence_refs'])) {
      if (r['kind'] == 'DELIVERY' && r['line_id'] != null) return r['line_id'];
    }
    for (final r in objects(tx['receipts'])) {
      if (r['target_delivery_line_id'] != null) return r['target_delivery_line_id'];
    }
    return null;
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final title = _step == _Step.card ? '확인 카드' : '저장 전 확인';
    final period = ref.watch(settlementProvider(widget.periodId));
    final detail = ref.watch(transactionProvider(widget.transactionId));
    if (period.hasError || !period.hasValue) {
      return Screen(title: title, children: [
        loaded(period, (_) => const SizedBox.shrink(),
            retry: () => refreshPeriod(ref, widget.periodId)),
      ]);
    }
    final data = period.requireValue;
    final item = objects(data['items'])
        .where((i) => i['transaction_id']?.toString() == widget.transactionId)
        .firstOrNull;
    if (item == null) {
      return Screen(
        title: title,
        children: const [
          Text('최신 정산에서 이 거래를 찾지 못했습니다.', style: Txt.section),
          SizedBox(height: 8),
          Text('자료가 바뀌었을 수 있습니다. 정산 홈에서 확인할 거래를 다시 골라 주세요.', style: Txt.label),
        ],
        bottom: [
          FilledButton(
              onPressed: () => context.go(periodRoute(widget.periodId)),
              child: const Text('정산 홈으로')),
        ],
      );
    }
    final tx = {...object(detail.valueOrNull), ...item};
    final revision = data['input_revision'];
    final supplier = supplierName(ref, tx['supplier_name'] != null ? tx : data);
    final header = [
      if (period.isLoading || detail.isLoading)
        const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
      _Header(tx, supplier),
      const SizedBox(height: 20),
    ];
    return PopScope(
      canPop: _step == _Step.card && !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _Step.review && !_recording) _cancelReview();
      },
      child: _step == _Step.card
          ? _card(title, header, tx, detail, revision)
          : _review(title, header, tx, revision),
    );
  }

  Widget _card(String title, List<Widget> header, Json tx, AsyncValue<Json> detail, Object? revision) {
    final receipts = objects(tx['receipts']);
    final memos = objects(tx['memos']);
    final delta = decimal(tx['delta_qty']);
    final locked = _busy || revision == null;
    // Without the loaded receipts a correction would be sent as a second,
    // unsuperseded receipt entry, so the button waits for the detail.
    final receiptsKnown = detail.hasValue && !detail.hasError;
    return Screen(
      title: title,
      children: [
        ...header,
        ...gap([
          InfoRow('거래처 명세서', qtyText(tx, 'declared_qty')),
          InfoRow('청구서', qtyText(tx, 'billed_qty')),
          InfoRow('점주 수령 기록', receivedText(tx),
              caption: tx['received_qty'] == null
                  ? '수령 기록을 연결하거나 직접 입력하세요'
                  : decimal(tx['received_qty']) == 0
                      ? '${receivedText(tx)}으로 확인한 기록'
                      : null),
          if (tx['check_amount'] != null)
            InfoRow('확인할 차이', '${deltaText(tx)} · ${won(tx['check_amount'])}',
                caption: delta != null && delta < 0
                    ? '수령 기록이 청구보다 많음 · 승인액이 아닌 산술 차이입니다'
                    : '승인액이 아닌 산술 차이입니다'),
        ], 10),
        const SizedBox(height: 20),
        const TintCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('이 납품 건의 계량표가 있나요?', style: Txt.section),
            SizedBox(height: 8),
            Text('두 기록과 청구서의 해당 줄을 볼 수 있어요.', style: Txt.label),
          ]),
        ),
        const SizedBox(height: 16),
        EvidenceButtons(objects(tx['evidence_refs'])),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: locked || _recording || !receiptsKnown ? null : () => _editReceipt(tx, revision),
          icon: const Icon(Icons.edit_note),
          label: Text(receipts.isEmpty
              ? '수령 근거 직접 입력'
              : '수령 근거 정정 · ${qtyText(receipts.last, 'received_qty')}'),
        ),
        const SectionTitle('거래처 답변', caption: '통화가 끝났다면 들은 내용을 남겨 주세요.'),
        if (detail.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              const Expanded(child: Text('저장된 통화 메모를 불러오지 못했습니다.', style: Txt.label)),
              TextButton(
                  onPressed: () => ref.invalidate(transactionProvider(widget.transactionId)),
                  child: const Text('다시 불러오기')),
            ]),
          ),
        for (final memo in memos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MemoCard(memo, receivedText(tx)),
          ),
        FilledButton(
          onPressed: locked ? null : _toggleRecording,
          child: Text(_recording
              ? '녹음 끝내기'
              : _transcribing
                  ? '받아쓰는 중…'
                  : '말로 남기기'),
        ),
        if (_recording) ...[
          const SizedBox(height: 8),
          const Text('녹음 중입니다. 말을 마치면 녹음 끝내기를 누르세요.',
              style: TextStyle(fontSize: 13, color: Palette.errInk, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy || _recording
              ? null
              : () {
                  _memo.clear();
                  _openReview(voice: false);
                },
          child: const Text('직접 입력'),
        ),
        const SizedBox(height: 10),
        const Text('녹음할 수 없으면 직접 입력으로 이어갑니다.', style: Txt.label),
      ],
      bottom: [
        OutlinedButton(
          onPressed: _recording ? null : () => context.go(periodRoute(widget.periodId)),
          child: const Text('나중에 확인'),
        ),
      ],
    );
  }

  Widget _review(String title, List<Widget> header, Json tx, Object? revision) => Screen(
        title: title,
        children: [
          ...header,
          InfoRow('거래처 명세서', qtyText(tx, 'declared_qty')),
          const SizedBox(height: 10),
          InfoRow('점주 수령 기록', receivedText(tx)),
          const SizedBox(height: 24),
          Text(_voice ? '말한 내용을 확인해 주세요' : '들은 내용을 적어 주세요', style: Txt.section),
          const SizedBox(height: 12),
          TextField(
            controller: _memo,
            focusNode: _memoFocus,
            minLines: 4,
            maxLines: 8,
            enabled: !_busy && !_recording,
            style: const TextStyle(fontSize: 16, color: Palette.ink, height: 1.55),
            decoration: const InputDecoration(
              hintText: '예: 거래처는 40kg을 보냈다고 합니다. 우리 기록은 36kg입니다.',
              contentPadding: EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 8),
          const Text('점주가 남긴 통화 메모', style: Txt.label),
          const SizedBox(height: 20),
          TintCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('저장 후에도 ${itemStatus(tx).text}', style: Txt.section),
              const SizedBox(height: 8),
              const Text('거래처 답변과 점주 수령 기록을 함께 남겨요.', style: Txt.label),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _recording ? null : _memoFocus.requestFocus,
                child: const Text('내용 수정'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _toggleRecording,
                child: Text(_recording ? '녹음 끝내기' : '다시 말하기'),
              ),
            ),
          ]),
        ],
        bottom: [
          FilledButton(
            onPressed: _busy || _recording || revision == null ? null : () => _saveMemo(revision),
            child: _busy
                ? const SizedBox.square(
                    dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('답변 저장 · 이 거래만 다시 대조'),
          ),
          TextButton(
            onPressed: _busy || _recording ? null : _cancelReview,
            child: const Text('취소'),
          ),
        ],
      );
}

class _Header extends StatelessWidget {
  const _Header(this.tx, this.supplier);
  final Json tx;
  final String supplier;

  @override
  Widget build(BuildContext context) {
    final caption = [tx['delivery_no'], tx['item']].where((v) => v != null).join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$supplier · ${dayText(tx['delivery_date'])} 납품', style: Txt.section),
      if (caption.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(caption, style: Txt.label),
      ],
      const SizedBox(height: 12),
      StatusChip(itemStatus(tx)),
    ]);
  }
}

/// Saved owner call memo, shown next to the store receipt value it answers.
class _MemoCard extends StatelessWidget {
  const _MemoCard(this.memo, this.received);
  final Json memo;
  final String received;

  static String _when(Object? iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      memo['source_mode'] == 'VOICE_MEMO' ? '음성' : '직접 입력',
      memo['author'],
      _when(memo['confirmed_at']),
    ].where((v) => v != null && v.toString().isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.record_voice_over_outlined, size: inlineIconSize, color: Palette.primary),
          const SizedBox(width: 6),
          const Expanded(
              child: Text('점주가 남긴 통화 메모',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.primary))),
        ]),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(meta, style: Txt.caption),
        ],
        const SizedBox(height: 10),
        Text((memo['confirmed_text'] ?? '').toString(), style: Txt.body),
        const Divider(height: 24, color: Palette.line),
        Row(children: [
          const Expanded(child: Text('점포 수령 기록', style: Txt.label)),
          Text(received, style: Txt.value),
        ]),
      ]),
    );
  }
}

typedef _ReceiptInput = ({String qty, String unit, String reason});

/// Dialog for entering or correcting the store receipt of one delivery row.
/// A confirmed zero ("0") is a valid entry (R01).
Future<_ReceiptInput?> _receiptForm(BuildContext context, Json? previous, Object? unit) {
  final form = GlobalKey<FormState>();
  var qty = (previous?['received_qty'] ?? '').toString();
  var unitText = (previous?['unit'] ?? unit ?? '').toString();
  var reason = '';
  return showDialog<_ReceiptInput>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(previous == null ? '수령 근거 직접 입력' : '수령 근거 정정'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              initialValue: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => qty = v.trim(),
              decoration: const InputDecoration(
                  labelText: '받은 수량', helperText: '받지 못했다면 0을 입력하세요.'),
              validator: (_) => RegExp(r'^\d+(\.\d+)?$').hasMatch(qty) ? null : '숫자로 입력하세요.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: unitText,
              onChanged: (v) => unitText = v.trim(),
              decoration: const InputDecoration(labelText: '단위'),
              validator: (_) => unitText.isEmpty ? '단위를 입력하세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              onChanged: (v) => reason = v.trim(),
              maxLines: 2,
              decoration: const InputDecoration(labelText: '확인 근거', hintText: '예: 입고 직후 계량표 36kg'),
              validator: (_) => reason.isEmpty ? '근거를 입력하세요.' : null,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, (qty: qty, unit: unitText, reason: reason));
            }
          },
          child: const Text('저장'),
        ),
      ],
    ),
  );
}
