import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';
import 'photo_review.dart';

const _docTypes = ['DELIVERY', 'RECEIPT', 'INVOICE', 'CORRECTED_INVOICE'];

/// 자료 올리기: 원본 업로드 → 판독 줄과 원본 확인 → 수령 기록을 납품에 연결,
/// 수정 청구서의 대체 대상 확인 → 최신 정산 재조회.
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen(this.periodId, {this.initialDocument, super.key});
  final String? initialDocument;
  final String periodId;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  bool busy = false;
  String type = 'DELIVERY';

  /// Document shown in the detail card.
  late String? selectedId = widget.initialDocument;

  @override
  void didUpdateWidget(UploadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodId != widget.periodId || oldWidget.initialDocument != widget.initialDocument) {
      selectedId = widget.initialDocument;
      lastUpload = null;
    }
  }

  /// Response of the last upload or extraction retry (carries `duplicate`).
  Json? lastUpload;

  /// Same file + type keeps its request_key so a retry is not a new upload.
  String? uploadSignature;
  String? uploadKey;

  /// Confirmation keys per action, valid for one input_revision.
  final actionKeys = <String, String>{};
  Object? keyRevision;

  String get periodId => widget.periodId;

  String _actionKey(String action, Object? revision) {
    if (revision != keyRevision) {
      actionKeys.clear();
      keyRevision = revision;
    }
    return actionKeys[action] ??= requestKey();
  }

  Future<void> _run(Future<void> Function() action) async {
    final error = await guarded(context, (b) {
      if (mounted) setState(() => busy = b);
    }, action);
    if (!mounted) return;
    if (error is ApiError && error.stale) {
      refreshPeriod(ref, periodId);
      notify(context, '그사이 자료가 바뀌어 최신 정산을 다시 불러왔습니다. 내용을 확인한 뒤 다시 진행해 주세요.');
    }
  }

  Future<void> _pickAndUpload() async {
    if (!demo) { await startPhotoReview(context); return; }
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null || !mounted) return;
    final docType = type;
    final signature = '$docType|${file.name}|${file.size}';
    if (signature != uploadSignature) {
      uploadSignature = signature;
      uploadKey = requestKey();
    }
    final mime = switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    await _run(() async {
      final saved = await backend.upload('${periodPath(periodId)}/documents', file.bytes!,
          file.name, mime, {'doc_type': docType, 'request_key': uploadKey!});
      // Saved: a later pick of the same file is a new upload, so the server
      // answers with its own duplicate check (R07) instead of a key replay.
      uploadSignature = null;
      if (!mounted) return;
      setState(() {
        lastUpload = {'doc_type': docType, 'filename': file.name, ...saved};
        selectedId = saved['document_id']?.toString();
      });
      refreshPeriod(ref, periodId);
    });
  }

  Future<void> _retryExtraction(Json data, Json doc) => _run(() async {
        if (!demo) {
          final bytes = await backend.original(doc['document_id'].toString());
          if (!mounted) return;
          final ext = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8
              ? 'jpg' : bytes.length > 11 && bytes[0] == 0x52 && bytes[8] == 0x57 ? 'webp' : 'png';
          final filename = (doc['filename']?.toString() ?? 'original').replaceFirst(RegExp(r'\.[^.]+$'), '');
          final route = await Navigator.of(context).push<String>(MaterialPageRoute(
            builder: (_) => PhotoReview(
              PlatformFile(name: '$filename.$ext', bytes: bytes, size: bytes.length),
              // Same document type, store, supplier and week as the failed reading.
              // A document shown here as another supplier's candidate keeps its own
              // supplier; the week is then chosen by date among that supplier's weeks.
              existing: {
                'doc_type': doc['doc_type'],
                'store_id': data['store_id'],
                'supplier_id': doc['selected_supplier_id'] ?? data['supplier_id'],
                if ((doc['selected_supplier_id'] ?? data['supplier_id']) == data['supplier_id'])
                  'period_id': data['period_id'] ?? periodId,
              },
            ),
          ));
          if (mounted && route != null) {
            setState(() => lastUpload = null);
            refreshPeriod(ref, periodId);
            context.go(route);
          }
          return;
        }
        final result =
            await backend.post('/api/documents/${part(doc['document_id'])}/extraction', {});
        if (!mounted) return;
        final upload = lastUpload;
        if (upload != null && upload['document_id']?.toString() == doc['document_id']?.toString()) {
          // Keep the upload's duplicate flag; the retry only replaces the reading.
          setState(() => lastUpload = {...upload, ...result, 'duplicate': upload['duplicate']});
        }
        refreshPeriod(ref, periodId);
        notify(context, result['extraction_status'] == 'COMPLETED' ? '다시 판독했습니다.' : '판독에 다시 실패했습니다.');
      });

  Future<void> _confirm(String action, Object? revision, Json fields, String done) => _run(() async {
        await backend.post('${periodPath(periodId)}/confirmations', {
          ...fields,
          'expected_revision': revision,
          'request_key': _actionKey(action, revision),
        });
        if (!mounted) return;
        refreshPeriod(ref, periodId);
        notify(context, done);
      });

  // ------------------------------------------------------------ receipt link

  Future<void> _linkReceipt(Json data, Json doc, Json line) async {
    final receipt = _Choice(
      heading: '점포 수령 기록',
      title: _lineTitle(line),
      value: qtyText(line, 'qty_read'),
      caption: locationText(line['source_location']),
      original: _lineRef(doc, line),
    );
    final items = objects(data['items']);
    final candidates = _matchesFirst([
      for (final delivery in objects(data['documents']))
        if (delivery['doc_type'] == 'DELIVERY' && _otherSupplier(data, delivery) == null)
          for (final l in objects(delivery['lines']))
            if (l['line_id'] != null)
              _Choice(
                heading: '납품 명세서',
                title: _lineTitle(l),
                value: qtyText(l, 'qty_read'),
                caption: _deliveryCaption(items, l),
                original: _lineRef(delivery, l),
                id: l['line_id'],
                match: line['delivery_no'] != null && l['delivery_no'] == line['delivery_no'],
              ),
    ]);
    if (candidates.isEmpty) {
      notify(context, '연결할 납품 명세가 없습니다. 납품 명세서를 먼저 올리거나 거래 화면에서 수령 근거를 직접 입력하세요.');
      return;
    }
    final matches = candidates.where((c) => c.match).length;
    final chosen = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickSheet(
        title: '수령 기록을 납품에 연결',
        guide: switch (matches) {
          1 => '명세 번호가 같은 납품을 먼저 골라 두었습니다. 두 원본을 확인한 뒤 연결해 주세요.',
          0 => '명세 번호가 일치하는 납품이 없습니다. 원본을 보고 직접 골라 주세요.',
          _ => '같은 명세 번호의 납품이 여러 건입니다. 원본을 보고 직접 골라 주세요.',
        },
        source: receipt,
        choices: candidates,
        preselect: matches == 1,
        selectedHeading: '선택한 납품',
        confirm: '이 납품으로 연결',
      ),
    );
    if (chosen == null || !mounted) return;
    await _confirm('receipt_link:${line['line_id']}:${chosen.id}', data['input_revision'], {
      'kind': 'receipt_link',
      'source_line_id': line['line_id'],
      'target_id': chosen.id,
      'evidence_refs': [receipt.original],
    }, '수령 기록을 ${chosen.title} 납품에 연결했습니다.');
  }

  /// Current received quantity of the delivery line, read from the settlement.
  static String _deliveryCaption(List<Json> items, Json line) {
    for (final item in items) {
      final refs = objects(item['evidence_refs']);
      if (refs.any((r) => r['kind'] == 'DELIVERY' && r['line_id'] == line['line_id'])) {
        return '현재 수령 ${receivedText(item)}';
      }
    }
    return locationText(line['source_location']);
  }

  // ------------------------------------------------------------- replacement

  Future<void> _confirmReplacement(Json data, Json doc) async {
    final history = objects(data['billing_history']);
    String amountOf(Object? id) {
      final entry = history.where((h) => h['document_id'] == id);
      return entry.isEmpty ? '' : won(entry.first['billed_amount']);
    }

    final corrected = _Choice(
      heading: '수정 청구서',
      title: (doc['doc_no'] ?? '번호 미확인').toString(),
      value: amountOf(doc['document_id']),
      caption: '대체 대상 ${doc['replaces_doc_no'] ?? '미확인'}',
      original: _agreementRef(doc),
    );
    final invoices = _matchesFirst([
      for (final invoice in objects(data['documents']))
        if (invoice['doc_type'] == 'INVOICE' && _otherSupplier(data, invoice) == null)
          _Choice(
            heading: '청구서',
            title: (invoice['doc_no'] ?? '번호 미확인').toString(),
            value: amountOf(invoice['document_id']),
            caption: (invoice['filename'] ?? '').toString(),
            original: {'document_id': invoice['document_id'], 'kind': 'INVOICE'},
            id: invoice['document_id'],
            match: doc['replaces_doc_no'] != null && invoice['doc_no'] == doc['replaces_doc_no'],
          ),
    ]);
    if (invoices.isEmpty) {
      notify(context, '대체할 기존 청구서가 없습니다. 청구서를 먼저 올려 주세요.');
      return;
    }
    final matches = invoices.where((c) => c.match).length;
    final chosen = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickSheet(
        title: '대체 대상 확인',
        guide: matches == 1
            ? '수정 청구서에 적힌 번호와 같은 청구서를 골라 두었습니다. 두 원본을 확인해 주세요.'
            : '수정 청구서가 대체할 청구서를 원본을 보고 직접 골라 주세요.',
        source: corrected,
        choices: invoices,
        preselect: matches == 1,
        selectedHeading: '대체될 청구서',
        confirm: '이 청구서를 대체',
      ),
    );
    if (chosen == null || !mounted) return;
    await _confirm('replacement:${doc['document_id']}:${chosen.id}', data['input_revision'], {
      'kind': 'replacement',
      'document_id': doc['document_id'],
      'target_id': chosen.id,
      'evidence_refs': [corrected.original],
    }, '${chosen.title} 청구서를 수정 청구서로 대체했습니다.');
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final settlement = ref.watch(settlementProvider(periodId));
    return Screen(
      title: '자료 올리기',
      homeEnabled: !busy,
      children: [
        loaded(settlement, _body, retry: () => ref.invalidate(settlementProvider(periodId))),
      ],
      bottom: [
        FilledButton(
          onPressed: () => context.go(periodRoute(periodId)),
          child: Text(keepWords('이 거래처 정산 보기')),
        ),
      ],
    );
  }

  Widget _body(Json data) {
    final documents = objects(data['documents']);
    final current = _current(documents);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${supplierName(ref, data)} · ${periodText(data)}', style: Txt.section),
      const SizedBox(height: 6),
      const Text('사진 한 장씩 올려 주세요. 판독한 줄은 원본과 함께 확인합니다.', style: Txt.label),
      const SizedBox(height: 20),
      if (demo) ...[
      const Text('자료 종류', style: Txt.label),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in _docTypes)
          ChoiceChip(
            label: Text(docTypeText(t)),
            selected: type == t,
            onSelected: busy ? null : (_) => setState(() => type = t),
          ),
      ]),
      const SizedBox(height: 16),
      ],
      FilledButton.icon(
        onPressed: busy ? null : _pickAndUpload,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(keepWords(documents.isEmpty ? '사진 선택해 올리기' : '사진 더 올리기')),
      ),
      if (busy) ...[
        const SizedBox(height: 10),
        const LinearProgressIndicator(),
      ],
      for (final id in (data['pending_removals'] as List? ?? const []))
        OutlinedButton(onPressed: busy ? null : () => _remove(id.toString()),
          child: Text(keepWords('원본 파일 삭제 마무리'))),
      if (current != null) ...[
        const SizedBox(height: 20),
        _documentCard(data, current),
      ],
      SectionTitle('올린 자료',
          caption: documents.isEmpty ? '아직 올린 자료가 없습니다.' : '눌러서 판독 줄과 연결 상태를 확인하세요.'),
      ...gap([
        for (final doc in documents)
          InfoRow(
            docTypeText(doc['doc_type']),
            _extractionText(doc),
            caption: [
              (doc['filename'] ?? '파일명 없음').toString(),
              if (doc['document_id']?.toString() == current?['document_id']?.toString()) '지금 보는 자료',
            ].join(' · '),
            valueColor: doc['extraction_status'] == 'FAILED' ? Palette.errInk : null,
            onTap: () => setState(() => selectedId = doc['document_id']?.toString()),
          ),
      ], 8),
    ]);
  }

  /// The selected document as the settlement has it now, or the upload
  /// response when the period does not list it (e.g. another supplier).
  Json? _current(List<Json> documents) {
    if (selectedId == null) return null;
    for (final doc in documents) {
      if (doc['document_id']?.toString() == selectedId) return doc;
    }
    return lastUpload?['document_id']?.toString() == selectedId ? lastUpload : null;
  }

  Future<void> _remove(String id) => _run(() async {
    try {
      await backend.post('${periodPath(periodId)}/documents/${part(id)}/remove', {});
      if (mounted) {
        setState(() { selectedId = null; lastUpload = null; uploadKey = null; uploadSignature = null; });
        notify(context, '자료를 삭제했습니다.');
      }
    } finally {
      if (mounted) refreshPeriod(ref, periodId);
    }
  });

  Future<void> _askRemove(Json doc) async {
    final accepted = await showDialog<bool>(context: context, builder: (dialog) =>
      AlertDialog(title: Text(keepWords('올린 자료를 삭제할까요?')),
        scrollable: true,
        content: Text('${doc['filename'] ?? '이 파일'}의 판독 행과 원본을 삭제합니다. 승인이나 확인에 쓰인 자료는 보존됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('삭제')),
        ]));
    if (accepted == true && mounted) await _remove(doc['document_id'].toString());
  }

  Future<void> _editTradeDate(Json doc) async {
    final initial = DateTime.tryParse((doc['trade_date'] ?? doc['doc_date'] ?? '').toString());
    final chosen = await showDatePicker(context: context, initialDate: initial != null && initial.year >= 1900 && initial.year < 2200 ? initial : DateTime.now(),
      firstDate: DateTime(1900), lastDate: DateTime(2200), initialEntryMode: DatePickerEntryMode.input,
      helpText: '원본에서 확인한 거래일', confirmText: '거래일 저장');
    if (chosen == null || !mounted) return;
    await _run(() async {
      await backend.post('${periodPath(periodId)}/documents/${part(doc['document_id'])}/trade-date',
        {'expected': doc['trade_date'], 'trade_date': chosen.toIso8601String().split('T').first});
      if (mounted) {refreshPeriod(ref, periodId); notify(context, '거래일을 저장했습니다.');}
    });
  }

  Widget _documentCard(Json data, Json doc) {
    final docType = doc['doc_type'];
    final lines = objects(doc['lines']);
    final failed = doc['extraction_status'] == 'FAILED';
    final isLastUpload = lastUpload?['document_id']?.toString() == doc['document_id']?.toString();
    final duplicate = isLastUpload && lastUpload!['duplicate'] == true;
    final mismatch = _otherSupplier(data, doc);
    final otherSupplier = mismatch != null;
    final linkedReceipts = _linkedReceiptLines(objects(data['items']));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (isLastUpload) ...[
          StatusChip(duplicate
              ? Status(keepWords('이미 저장된 파일입니다 · 기존 자료를 다시 보여 드려요'), Tone.info)
              : const Status('원본 저장 완료', Tone.ok)),
          const SizedBox(height: 10),
        ],
        Text(docTypeText(docType), style: Txt.section),
        const SizedBox(height: 4),
        Text([
          (doc['filename'] ?? '파일명 없음').toString(),
          if (doc['doc_no'] != null) doc['doc_no'].toString(),
        ].join(' · '), style: Txt.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Text('거래일 · ${doc['trade_date'] ?? '미확인'}', style: Txt.body),
        for (final entry in statementAmountLabels.entries)
          if (doc[entry.key] != null)
            Text('${entry.value} · ${won(doc[entry.key])}', style: Txt.label),
        if (doc['doc_date'] != null) Text('문서일 · ${doc['doc_date']}', style: Txt.label),
        if (doc['issued_on'] != null) Text('작성·발행일 · ${doc['issued_on']}', style: Txt.label),
        if (doc['quoted_on'] != null) Text('견적일 · ${doc['quoted_on']}', style: Txt.label),
        if (doc['source_date_text'] != null) Text('원본 날짜 표기 · ${doc['source_date_text']}', style: Txt.label),
        if (!demo && doc['source_mode'] == 'FILE') Wrap(children: [
          TextButton(onPressed: busy ? null : () => _editTradeDate(doc), child: const Text('거래일 수정')),
          TextButton(onPressed: busy ? null : () => _askRemove(doc), child: const Text('자료 삭제')),
        ]),
        StatusChip(Status(_extractionText(doc), failed ? Tone.error : Tone.neutral)),
        if (mismatch != null) ...[
          const SizedBox(height: 12),
          TintCard(
            color: Palette.warnBg,
            child: Text('원본의 거래처(${mismatch.read})가 선택한 거래처(${mismatch.expected})와 다릅니다. 이 정산에 합치지 않습니다.',
                style: Txt.body.copyWith(color: Palette.warnInk)),
          ),
        ],
        if (failed) ...[
          const SizedBox(height: 12),
          const Text('원본은 저장되어 있습니다. 같은 원본으로 판독을 다시 시도할 수 있어요.', style: Txt.label),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : () => _retryExtraction(data, doc),
            child: const Text('판독 다시 시도'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showOriginal(context, {'document_id': doc['document_id'], 'kind': docType}),
          child: const Text('원본 보기'),
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(keepWords('판독한 줄 · 누르면 원본의 해당 줄을 엽니다'), style: Txt.label),
          const SizedBox(height: 8),
          for (final line in lines) ...[
            InfoRow(
              line['delivery_date'] == null ? '행 납품일 미기재 · ${line['delivery_no'] ?? '번호 미확인'}' : _lineTitle(line),
              qtyText(line, 'qty_read'),
              caption: [
                if (line['item'] != null) line['item'].toString(),
                if (line['spec'] != null) '규격 ${line['spec']}',
                if (line['item_code'] != null) '코드 ${line['item_code']}',
                if (line['origin'] != null) '원산지 ${line['origin']}',
                if (line['lot_no'] != null) '로트 ${line['lot_no']}',
                if (line['line_note'] != null) '비고 ${line['line_note']}',
                '단가 ${won(line['unit_price_corrected'] ?? line['unit_price_read'])}',
                '금액 ${won(line['amount_corrected'] ?? line['amount_read'])}',
                if (line['supply_amount_read'] != null) '공급가액 ${won(line['supply_amount_read'])}',
                if (line['discount_amount_read'] != null) '할인액 ${won(line['discount_amount_read'])}',
                if (line['line_total_read'] != null) '합계금액 ${won(line['line_total_read'])}',
                if (line['tax_amount_read'] != null) '세액 ${won(line['tax_amount_read'])}',
                if (line['line_date_text'] != null) '품목 날짜 ${line['line_date_text']}',
                locationText(line['source_location']),
              ].join(' · '),
              onTap: () => showOriginal(context, _lineRef(doc, line)),
            ),
            if (docType == 'RECEIPT' && !otherSupplier && line['line_id'] != null)
              _receiptAction(data, doc, line, linkedReceipts[line['line_id']]),
            const SizedBox(height: 8),
          ],
        ],
        if (docType == 'CORRECTED_INVOICE' && !otherSupplier) ...[
          const SizedBox(height: 8),
          _replacementCard(data, doc),
        ],
      ]),
    );
  }

  /// Supplier read from [doc] and the period's supplier when they differ
  /// (R02: such a document is never linked into this settlement).
  ({String read, String expected})? _otherSupplier(Json data, Json doc) {
    final read = doc['supplier_name_read']?.toString().trim();
    final expected = (data['supplier_name'] ?? ref.read(pickedNames)['supplier'])?.toString().trim();
    if (read == null || expected == null || read == expected) return null;
    return (read: read, expected: expected);
  }

  /// Receipt line id → delivery number it is linked to in the settlement.
  static Map<Object?, String> _linkedReceiptLines(List<Json> items) => {
        for (final item in items)
          for (final r in objects(item['evidence_refs']))
            if (r['kind'] == 'RECEIPT' && r['line_id'] != null)
              r['line_id']: (item['delivery_no'] ?? '납품').toString(),
      };

  Widget _receiptAction(Json data, Json doc, Json line, String? linkedTo) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: linkedTo != null
            ? Row(children: [
                const Icon(Icons.check_circle, size: inlineIconSize, color: Palette.okInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('연결됨 · $linkedTo',
                      style: const TextStyle(
                          fontFamily: appFont,
                          fontSize: 13, fontWeight: FontWeight.w700, color: Palette.okInk)),
                ),
              ])
            : OutlinedButton.icon(
                onPressed: busy ? null : () => _linkReceipt(data, doc, line),
                icon: const Icon(Icons.link),
                label: const Text('납품에 연결'),
              ),
      );

  Widget _replacementCard(Json data, Json doc) {
    final agreement = doc['agreement_text'];
    final confirmed = objects(data['billing_history']).any((h) =>
        h['document_id']?.toString() == doc['document_id']?.toString() && h['status'] == 'CURRENT');
    return TintCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('수정 청구 확인', style: Txt.section),
        const SizedBox(height: 10),
        Text('대체 대상 ${doc['replaces_doc_no'] ?? '미확인'}', style: Txt.value),
        const SizedBox(height: 10),
        const Text('합의 문구', style: Txt.label),
        const SizedBox(height: 4),
        Text(agreement == null ? '양측 확인 문구를 찾지 못했습니다' : '“$agreement”', style: Txt.body),
        if (agreement == null) ...[
          const SizedBox(height: 10),
          TintCard(
            color: Palette.warnBg,
            child: Text('합의 근거가 없어 대체를 확인해도 수량 차이는 승인 전까지 막혀 있습니다.',
                style: Txt.body.copyWith(color: Palette.warnInk)),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showOriginal(context, _agreementRef(doc)),
          child: Text(keepWords('수정 청구서 원본 보기')),
        ),
        const SizedBox(height: 10),
        if (confirmed)
          const StatusChip(Status('대체 확인됨', Tone.ok))
        else
          FilledButton(
            onPressed: busy ? null : () => _confirmReplacement(data, doc),
            child: const Text('대체 대상 확인'),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- helpers

  static List<_Choice> _matchesFirst(List<_Choice> all) =>
      [...all.where((c) => c.match), ...all.where((c) => !c.match)];

  static String _lineTitle(Json line) =>
      '${dayText(line['delivery_date'])} ${line['delivery_no'] ?? '번호 미확인'}';

  static Json _lineRef(Json doc, Json line) => {
        'document_id': line['document_id'] ?? doc['document_id'],
        'line_id': line['line_id'],
        'kind': doc['doc_type'],
        'source_location': line['source_location'],
      };

  static Json _agreementRef(Json doc) => {
        'document_id': doc['document_id'],
        'line_id': null,
        'kind': 'CORRECTED_INVOICE',
        'source_location': doc['agreement_source_location'],
      };

  static String _extractionText(Json doc) => switch (doc['extraction_status']) {
        'COMPLETED' => '판독 완료 · ${objects(doc['lines']).length}줄',
        'FAILED' => '판독 실패',
        'PENDING' || 'PROCESSING' => '판독 중',
        _ => '판독 상태 미확인',
      };
}

/// One row the owner can pick (a delivery line or an invoice) or the row
/// being linked, with the reference that opens its original.
class _Choice {
  const _Choice({
    required this.heading,
    required this.title,
    required this.value,
    required this.caption,
    required this.original,
    this.id,
    this.match = false,
  });
  final String heading;
  final String title;
  final String value;
  final String caption;
  final Json original;
  final Object? id;
  final bool match;
}

/// Bottom sheet: the source row and the chosen target side by side, each
/// with its original, and a candidate list. Returns the target only on the
/// explicit confirm button (R02: never links on its own).
class _PickSheet extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.guide,
    required this.source,
    required this.choices,
    required this.preselect,
    required this.selectedHeading,
    required this.confirm,
  });
  final String title;
  final String guide;
  final _Choice source;
  final List<_Choice> choices;
  final bool preselect;
  final String selectedHeading;
  final String confirm;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late _Choice? selected = widget.preselect ? widget.choices.firstWhere((c) => c.match) : null;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(keepWords(widget.title), style: Txt.title),
              const SizedBox(height: 6),
              Text(widget.guide, style: Txt.label),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _SideCard(widget.source.heading, widget.source)),
                  const SizedBox(width: 10),
                  Expanded(child: _SideCard(widget.selectedHeading, selected)),
                ]),
              ),
              const SizedBox(height: 20),
              Text('후보 ${widget.choices.length}건', style: Txt.section),
              const SizedBox(height: 10),
              ...gap([
                for (final c in widget.choices) _candidate(c),
              ], 8),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: selected == null ? null : () => Navigator.pop(context, selected),
                child: Text(keepWords(widget.confirm)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
            ]),
          ),
        ),
      );

  Widget _candidate(_Choice c) {
    final isSelected = identical(c, selected);
    return Material(
      color: isSelected ? Palette.tint : Palette.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? Palette.primary : Palette.line, width: isSelected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => selected = c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: inlineIconSize, color: isSelected ? Palette.primary : Palette.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: Txt.value, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(c.caption, style: Txt.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (c.match) ...[
                  const SizedBox(height: 6),
                  const StatusChip(Status('명세 번호 일치', Tone.info)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            // Amounts have no spaces: shrink instead of wrapping or overflowing.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(c.value, style: Txt.value, maxLines: 1),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard(this.heading, this.choice);
  final String heading;
  final _Choice? choice;

  @override
  Widget build(BuildContext context) {
    final c = choice;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(keepWords(heading), style: Txt.caption),
        const SizedBox(height: 6),
        if (c == null)
          Expanded(child: Text(keepWords('아래 후보에서 골라 주세요'), style: Txt.label))
        else ...[
          Text(c.title,
              style: Txt.body.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (c.value.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(c.value, style: Txt.amount, maxLines: 1),
            ),
          Text(c.caption, style: Txt.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          const Spacer(),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            onPressed: () => showOriginal(context, c.original),
            child: const Text('원본 보기'),
          ),
        ],
      ]),
    );
  }
}
