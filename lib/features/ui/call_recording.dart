import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';
import 'start_button.dart';

/// Call recording file types the transcription server accepts.
const callExtensions = ['m4a', 'mp4', 'mp3', 'wav', 'webm', 'ogg', 'flac'];

/// OpenAI's transcription upload limit, mirrored by POST /api/transcriptions.
const callMaxBytes = 25 * 1024 * 1024;

String callMime(String? extension) => switch (extension?.toLowerCase()) {
      'm4a' => 'audio/x-m4a',
      'mp4' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'webm' => 'audio/webm',
      'ogg' => 'audio/ogg',
      'flac' => 'audio/flac',
      _ => 'application/octet-stream',
    };

String transcriptionError(Object error) => switch (error) {
      ApiError(detail: 'EMPTY_AUDIO') => '녹음이 비어 있습니다.',
      ApiError(detail: 'AUDIO_TOO_LARGE') => '녹음이 25MB를 넘습니다.',
      ApiError(detail: 'UNSUPPORTED_AUDIO') => '지원하지 않는 녹음 형식입니다.',
      _ => '받아쓰기를 하지 못했습니다.',
    };

/// A call recording file turned into an editable 통화 메모 for one delivery.
/// The audio is only sent for transcription and never stored (R04); the
/// owner's edited text is saved through the same memo path as 말로 남기기.
class CallRecordingReview extends ConsumerStatefulWidget {
  const CallRecordingReview(this.file, {super.key, this.api});
  final Backend? api;
  final PlatformFile file;
  @override
  ConsumerState<CallRecordingReview> createState() =>
      _CallRecordingReviewState();
}

class _CallRecordingReviewState extends ConsumerState<CallRecordingReview> {
  Backend get api => widget.api ?? backend;
  final memo = TextEditingController();
  List<Json> stores = [], suppliers = [], periods = [], items = [];
  String? store, supplier, period, transaction, error, readError;
  Object? revision;
  bool reading = true, saving = false, loadingChoices = false;
  String keyForSave = requestKey();
  String? lastPayload;

  @override
  void initState() {
    super.initState();
    _read();
    _loadStores();
  }

  @override
  void dispose() {
    memo.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      reading = true;
      readError = null;
    });
    try {
      final result = await api.upload(
        '/api/transcriptions',
        widget.file.bytes!,
        widget.file.name,
        callMime(widget.file.extension),
      );
      if (!mounted) return;
      memo.text = (result['draft_text'] ?? '').toString();
    } catch (e) {
      if (mounted) {
        setState(
          () => readError = '${transcriptionError(e)} 들은 내용을 직접 입력해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> _choices(Future<void> Function() load) async {
    setState(() {
      loadingChoices = true;
      error = null;
    });
    try {
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loadingChoices = false);
    }
  }

  Future<void> _loadStores() => _choices(() async {
        final list = records(await api.get('/api/stores'), 'stores');
        if (!mounted) return;
        setState(() => stores = list);
        if (list.length == 1) await _store('${list.single['id']}');
      });

  Future<void> _store(String id) {
    setState(() {
      store = id;
      supplier = period = transaction = null;
      suppliers = periods = items = [];
    });
    return _choices(() async {
      final list = records(
        await api.get('/api/suppliers?store_id=${part(id)}'),
        'suppliers',
      );
      if (!mounted || store != id) return;
      setState(() => suppliers = list);
      if (list.length == 1) await _supplier('${list.single['id']}');
    });
  }

  Future<void> _supplier(String id) {
    setState(() {
      supplier = id;
      period = transaction = null;
      periods = items = [];
    });
    return _choices(() async {
      final list = records(
        await api.get(
          '/api/periods?store_id=${part(store)}&supplier_id=${part(id)}',
        ),
        'periods',
      );
      if (!mounted || supplier != id) return;
      setState(() => periods = list);
      if (list.isNotEmpty) await _period('${list.first['period_id']}');
    });
  }

  Future<void> _period(String id) {
    setState(() {
      period = id;
      transaction = null;
      items = [];
    });
    return _choices(() async {
      final data = object(await api.get(periodPath(id)));
      if (!mounted || period != id) return;
      final list = objects(data['items'])
          .where((i) => i['transaction_id'] != null)
          .toList();
      setState(() {
        items = list;
        revision = data['input_revision'];
        if (list.length == 1) transaction = '${list.single['transaction_id']}';
      });
    });
  }

  String _itemText(Json item) => [
        dayText(item['delivery_date']),
        if (item['item'] != null) item['item'],
        if (item['billed_qty'] != null) '청구 ${qtyText(item, 'billed_qty')}',
      ].join(' · ');

  Future<void> _save() async {
    final text = memo.text.trim();
    if (text.isEmpty) {
      setState(() => error = '저장할 통화 내용을 입력하세요.');
      return;
    }
    final body = {
      'confirmed_text': text,
      'source_mode': 'VOICE_MEMO',
      'expected_revision': revision,
    };
    final payload = '$transaction|$text|$revision';
    if (lastPayload != payload) {
      keyForSave = requestKey();
      lastPayload = payload;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await api.post('/api/transactions/${part(transaction)}/memos', {
        ...body,
        'request_key': keyForSave,
      });
      if (!mounted) return;
      ref.read(pickedNames.notifier).state = {
        'store':
            stores.firstWhere((s) => '${s['id']}' == store)['name'].toString(),
        'supplier': suppliers
            .firstWhere((s) => '${s['id']}' == supplier)['name']
            .toString(),
      };
      refreshPeriod(ref, period!);
      Navigator.pop(context, transactionRoute(period!, transaction));
    } catch (e) {
      if (!mounted) return;
      final stale = e is ApiError && e.stale;
      setState(() => error = e.toString());
      // The period changed under us: reload its revision before the retry.
      if (stale) await _period(period!);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _choice(
    String label,
    String? value,
    Map<String, String> options,
    void Function(String) change,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey([label, value, options.keys.join(',')].join('|')),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: saving || loadingChoices
              ? null
              : (v) {
                  if (v != null) change(v);
                },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final errorStyle = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(title: const Text('통화녹음으로 메모 남기기'), actions: [
        StartButton(enabled: !saving, draft: memo.text.isNotEmpty || !reading, returnRoute: true),
      ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TintCard(
                    child: Row(
                      children: [
                        const Icon(Icons.call_outlined, color: Palette.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.file.name,
                            style: Txt.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('녹음 파일은 받아쓰기에만 쓰고 보관하지 않습니다.', style: Txt.caption),
                  const SectionTitle(
                    '통화 내용',
                    caption: '받아쓴 초안입니다. 틀린 부분을 고친 뒤 저장하세요.',
                  ),
                  if (reading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('녹음을 받아쓰는 중입니다.', style: Txt.label),
                    const SizedBox(height: 8),
                  ],
                  if (readError != null) ...[
                    Text(readError!, style: errorStyle),
                    TextButton(
                      onPressed: reading ? null : _read,
                      child: const Text('다시 받아쓰기'),
                    ),
                  ],
                  TextField(
                    controller: memo,
                    enabled: !reading && !saving,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(labelText: '통화 메모'),
                  ),
                  const SectionTitle('어느 거래의 통화인가요?'),
                  // A new browser has no stores until a photo registers one.
                  if (stores.isEmpty && !loadingChoices && error == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '이 브라우저에 등록된 점포가 없습니다. 먼저 사진 올리기로 거래처 자료를 등록한 뒤 통화 메모를 남겨 주세요. 받아쓴 내용은 복사해 두세요.',
                        style: Txt.label,
                      ),
                    ),
                  if (stores.isEmpty && !loadingChoices)
                    TextButton(
                      onPressed: _loadStores,
                      child: const Text('점포 목록 다시 불러오기'),
                    ),
                  _choice(
                      '점포',
                      store,
                      {
                        for (final s in stores) '${s['id']}': '${s['name']}',
                      },
                      _store),
                  _choice(
                      '거래처',
                      supplier,
                      {
                        for (final s in suppliers) '${s['id']}': '${s['name']}',
                      },
                      _supplier),
                  _choice(
                      '정산 기간',
                      period,
                      {
                        for (final p in periods)
                          '${p['period_id']}': periodText(p),
                      },
                      _period),
                  _choice(
                      '품목',
                      transaction,
                      {
                        for (final i in items)
                          '${i['transaction_id']}': _itemText(i),
                      },
                      (v) => setState(() => transaction = v)),
                  if (supplier != null && periods.isEmpty && !loadingChoices)
                    const Text('이 거래처에 열려 있는 정산 기간이 없습니다.', style: Txt.label),
                  if (period != null && items.isEmpty && !loadingChoices)
                    const Text(
                      '이 기간에 메모를 남길 품목이 없습니다. 먼저 사진 자료를 올려 주세요.',
                      style: Txt.label,
                    ),
                  if (loadingChoices) const LinearProgressIndicator(),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: errorStyle),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        reading || saving || transaction == null ? null : _save,
                    child: Text(saving ? '저장 중' : '통화 메모 저장'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-button entry: pick a call recording file, then review it.
Future<void> startCallRecording(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: callExtensions,
    withData: true,
  );
  if (!context.mounted || picked == null || picked.files.single.bytes == null) {
    return;
  }
  final file = picked.files.single;
  if (file.size > callMaxBytes) {
    notify(context, '25MB 이하의 녹음 파일을 선택해 주세요.');
    return;
  }
  final route = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => CallRecordingReview(file)));
  if (context.mounted && route != null) {
    context.go(route);
    if (route == '/') return;
    notify(context, '통화 메모를 저장했습니다. 이 거래만 다시 대조합니다.');
  }
}
