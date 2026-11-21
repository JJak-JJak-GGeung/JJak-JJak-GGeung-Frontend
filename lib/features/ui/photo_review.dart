import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';

const photoTypes = ['DELIVERY', 'RECEIPT', 'INVOICE', 'CORRECTED_INVOICE'];

/// The file stays available on this page even during a failed or retried reading.
class PhotoReview extends ConsumerStatefulWidget {
  const PhotoReview(this.file, {super.key, this.api});
  final Backend? api;
  final PlatformFile file;
  @override
  ConsumerState<PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends ConsumerState<PhotoReview> {
  Backend get api => widget.api ?? backend;
  Json? preview;
  List<Json> lines = [], stores = [], suppliers = [], periods = [];
  String? store, supplier, period, type, error;
  bool reading = true, saving = false, loadingChoices = false;
  String keyForSave = requestKey();
  String? lastPayload;
  String get mime => switch (widget.file.extension?.toLowerCase()) {
    'jpeg' || 'jpg' => 'image/jpeg',
    'webp' => 'image/webp',
    _ => 'image/png',
  };

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final result = await api.upload(
        '/api/photo-previews',
        widget.file.bytes!,
        widget.file.name,
        mime,
      );
      if (!mounted) return;
      setState(() {
        preview = result;
        final draft = object(result['draft']);
        lines = objects(draft['lines'])
            .map((l) => Map<String, dynamic>.from(l))
            .toList();
        type = draft['doc_type'] as String?;
        reading = false;
      });
      await _loadStores();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> _loadStores() async {
    setState(() {
      loadingChoices = true;
      error = null;
    });
    try {
      final shops = records(await api.get('/api/stores'), 'stores');
      if (!mounted) return;
      setState(() => stores = shops);
      if (shops.length == 1) await _store(shops.single['id']);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loadingChoices = false);
    }
  }

  Future<void> _store(String id) async {
    setState(() {
      store = id;
      supplier = period = null;
      suppliers = [];
      periods = [];
      loadingChoices = true;
      error = null;
    });
    try {
      final list = records(
        await api.get('/api/suppliers?store_id=${part(id)}'),
        'suppliers',
      );
      if (!mounted || store != id) return;
      setState(() => suppliers = list);
      String norm(Object? v) =>
          (v ?? '').toString().replaceAll(RegExp(r'\s+'), '');
      final name = norm(object(preview?['draft'])['supplier_name_read']);
      final matches = list
          .where((s) => name.isNotEmpty && norm(s['name']) == name)
          .toList();
      if (matches.length == 1) await _supplier(matches.single['id']);
    } catch (e) {
      if (mounted && store == id) setState(() => error = e.toString());
    } finally {
      if (mounted && store == id) setState(() => loadingChoices = false);
    }
  }

  Future<void> _supplier(String id) async {
    setState(() {
      supplier = id;
      period = null;
      periods = [];
      error = null;
      loadingChoices = true;
    });
    try {
      final list = records(
        await api.get(
          '/api/periods?store_id=${part(store)}&supplier_id=${part(id)}',
        ),
        'periods',
      );
      if (!mounted || supplier != id) return;
      final date = object(preview?['draft'])['doc_date']?.toString();
      final matches = list
          .where(
            (p) =>
                date != null &&
                date.compareTo('${p['period_start']}') >= 0 &&
                date.compareTo('${p['period_end']}') <= 0,
          )
          .toList();
      setState(() {
        periods = list;
        if (matches.length == 1) period = matches.single['period_id'];
      });
    } catch (e) {
      if (mounted && supplier == id) setState(() => error = e.toString());
    } finally {
      if (mounted && supplier == id) setState(() => loadingChoices = false);
    }
  }

  void _original() => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('원본 사진'),
          leading: CloseButton(onPressed: () => Navigator.pop(ctx)),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 8,
            child: Image.memory(widget.file.bytes!, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );

  Future<void> _save() async {
    final edits = <Json>[];
    for (final l in lines) {
      String? val(String k) {
        final t = l[k]?.toString().trim() ?? '';
        return t.isEmpty ? null : t;
      }

      final amount = val('amount_read');
      final decimal = RegExp(r'^-?\d{1,16}(\.\d{1,8})?$');
      if (val('item') == null ||
          [
            val('qty_read'),
            val('unit_price_read'),
          ].any((v) => v != null && !decimal.hasMatch(v)) ||
          (amount != null && !RegExp(r'^-?\d{1,16}$').hasMatch(amount))) {
        setState(() => error = '품목명과 숫자 형식을 확인해 주세요. 모르는 수량·가격은 비워 둘 수 있습니다.');
        return;
      }
      edits.add({
        'item': val('item'),
        'unit': val('unit'),
        'qty_read': val('qty_read'),
        'unit_price_read': val('unit_price_read'),
        'amount_read': amount == null ? null : int.parse(amount),
      });
    }
    final payload = jsonEncode({
      'store_id': store,
      'supplier_id': supplier,
      'period_id': period,
      'doc_type': type,
      'lines': edits,
    });
    if (lastPayload != payload) {
      keyForSave = requestKey();
      lastPayload = payload;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await api.upload(
        '/api/photo-previews/confirm',
        widget.file.bytes!,
        widget.file.name,
        mime,
        {
          'draft_json': jsonEncode(preview!['draft']),
          'signature': preview!['signature'],
          'request_key': keyForSave,
          'review_json': payload,
        },
      );
      if (!mounted) return;
      ref.read(pickedNames.notifier).state = {
        'store': stores.firstWhere((s) => s['id'] == store)['name'],
        'supplier': suppliers.firstWhere((s) => s['id'] == supplier)['name'],
      };
      refreshPeriod(ref, period!);
      Navigator.pop(
        context,
        '${uploadRoute(period!)}?document=${part(result['document_id'])}',
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _choice(
    String label,
    String? value,
    Map<String, String> options,
    void Function(String) change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey([label, value, options.keys.join(',')].join('|')),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: saving || loadingChoices
          ? null
          : (v) {
              if (v != null) change(v);
            },
    ),
  );

  Widget _field(Json line, String key, String label) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      initialValue: line[key]?.toString() ?? '',
      enabled: !saving,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => line[key] = v,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final draft = object(preview?['draft']);
    final editor = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('판독값 확인', style: Txt.section),
        if (reading) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!reading && preview == null)
          OutlinedButton(onPressed: _read, child: const Text('다시 판독')),
        if (preview != null) ...[
          Text(
            '문서에서 읽은 거래처 · ${draft['supplier_name_read'] ?? '미확인'}',
            style: Txt.body,
          ),
          const SizedBox(height: 12),
          if (stores.isEmpty && !loadingChoices)
            TextButton(
              onPressed: _loadStores,
              child: const Text('점포 목록 다시 불러오기'),
            ),
          _choice('점포', store, {
            for (final s in stores) '${s['id']}': '${s['name']}',
          }, _store),
          _choice('저장할 거래처', supplier, {
            for (final s in suppliers) '${s['id']}': '${s['name']}',
          }, _supplier),
          _choice('정산 기간', period, {
            for (final p in periods) '${p['period_id']}': '${p['label']}',
          }, (v) => setState(() => period = v)),
          _choice('문서 종류', type, {
            for (final t in photoTypes) t: docTypeText(t),
          }, (v) => setState(() => type = v)),
          if (supplier != null && periods.isEmpty && !loadingChoices)
            const Text('이 거래처에 열려 있는 정산 기간이 없습니다.'),
          if (loadingChoices) const LinearProgressIndicator(),
          for (final (i, l) in lines.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('품목 ${i + 1}', style: Txt.section),
                    _field(l, 'item', '품목명'),
                    Row(
                      children: [
                        Expanded(child: _field(l, 'qty_read', '수량')),
                        const SizedBox(width: 8),
                        Expanded(child: _field(l, 'unit', '단위')),
                      ],
                    ),
                    _field(l, 'unit_price_read', '단가 (원)'),
                    _field(l, 'amount_read', '행 금액 (원)'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                reading ||
                    saving ||
                    period == null ||
                    type == null ||
                    lines.isEmpty
                ? null
                : _save,
            child: Text(saving ? '저장 중' : '판독값 확인하고 저장'),
          ),
        ],
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('사진으로 자료 등록'),
        actions: [
          TextButton.icon(
            onPressed: _original,
            icon: const Icon(Icons.image_outlined),
            label: const Text('원본 보기'),
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(
                    child: InteractiveViewer(
                      maxScale: 8,
                      child: Image.memory(
                        widget.file.bytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: editor),
                ],
              )
            : editor,
      ),
    );
  }
}

Future<void> startPhotoReview(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    withData: true,
  );
  if (!context.mounted || picked == null || picked.files.single.bytes == null)
    return;
  final file = picked.files.single;
  if (file.size > 10485760) {
    notify(context, '10MB 이하의 사진을 선택해 주세요.');
    return;
  }
  final route = await Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => PhotoReview(file)));
  if (context.mounted && route != null) context.go(route);
}
