import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';

const statementAmountLabels = {
  'supply_total': '공급가액 합계',
  'tax_total': '세액 합계',
  'document_total': '문서 합계금액',
  'previous_balance': '전잔액',
  'balance_after_dispatch': '전잔액 + 출고액',
  'deposit_amount': '입금액',
  'current_balance': '현잔액',
};

const _newChoice = '__new__';
const photoTypes = ['DELIVERY', 'RECEIPT', 'INVOICE', 'CORRECTED_INVOICE'];

/// The file stays available on this page even during a failed or retried reading.
class PhotoReview extends ConsumerStatefulWidget {
  const PhotoReview(this.file, {super.key, this.api, this.existing});
  final Backend? api;
  final PlatformFile file;

  /// Re-reading a stored original: its doc_type, store_id, supplier_id and
  /// period_id are preselected so the confirm completes that document instead
  /// of colliding with it (PHOTO_ALREADY_REGISTERED).
  final Json? existing;
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
  String shopName = '', vendorName = '';
  DateTime? week;
  String tradeDate = '';
  final amountInputs = <String, String>{};
  String? proposedDate(Json draft) => draft['trade_date'] ?? draft['doc_date'] ?? draft['issued_on'] ?? draft['quoted_on'];
  bool storesLoaded = false, suppliersLoaded = false, periodsLoaded = false;
  String? kept(String key) => widget.existing?[key]?.toString();

  String day(DateTime d) => d.toIso8601String().split('T').first;
  DateTime monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));
  bool get ready =>
      !loadingChoices &&
      storesLoaded &&
      suppliersLoaded &&
      periodsLoaded &&
      store != null &&
      supplier != null &&
      (store != _newChoice || shopName.trim().isNotEmpty) &&
      (supplier != _newChoice || vendorName.trim().isNotEmpty) &&
      period != null &&
      (period != _newChoice || week != null);

  Future<void> chooseWeek() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: week ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2200));
    if (picked != null && mounted) setState(() => week = monday(picked));
  }

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
        shopName = draft['store_name_read']?.toString() ?? '';
        vendorName = draft['supplier_name_read']?.toString() ?? '';
        amountInputs.clear();
        for (final key in statementAmountLabels.keys.where(draft.containsKey)) {
          amountInputs[key] = draft[key]?.toString() ?? '';
        }
        tradeDate = draft['trade_date']?.toString() ?? '';
        final date = DateTime.tryParse(proposedDate(draft) ?? '');
        if (date != null && date.year >= 1900 && date.year < 2200)
          week = monday(date);
        type = photoTypes.contains(kept('doc_type'))
            ? kept('doc_type')
            : photoTypes.contains(draft['doc_type']) ? draft['doc_type'] as String : null;
        reading = false;
      });
      await _loadStores();
    } catch (e) {
      if (mounted) setState(() => error = userErrorText(e));
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
      setState(() {
        stores = shops;
        storesLoaded = true;
      });
      final keepStore = kept('store_id');
      if (keepStore != null && shops.any((s) => '${s['id']}' == keepStore)) {
        await _store(keepStore);
        return;
      }
      final name = shopName.trim().toLowerCase();
      final matches = shops.where((s) => name.isNotEmpty &&
          s['name']?.toString().trim().toLowerCase() == name).toList();
      if (matches.length == 1) await _store(matches.single['id']);
    } catch (e) {
      if (mounted) setState(() => error = userErrorText(e));
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
      suppliersLoaded = periodsLoaded = false;
      loadingChoices = true;
      error = null;
    });
    try {
      if (id == _newChoice) {
        setState(() {
          supplier = period = _newChoice;
          suppliersLoaded = periodsLoaded = true;
        });
        return;
      }
      final list = records(
        await api.get('/api/suppliers?store_id=${part(id)}'),
        'suppliers',
      );
      if (!mounted || store != id) return;
      setState(() {
        suppliers = list;
        suppliersLoaded = true;
      });
      final keepSupplier = kept('supplier_id');
      if (keepSupplier != null && list.any((s) => '${s['id']}' == keepSupplier)) {
        await _supplier(keepSupplier);
        return;
      }
      String norm(Object? v) =>
          (v ?? '').toString().trim().toLowerCase();
      final name = norm(object(preview?['draft'])['supplier_name_read']);
      final matches = list
          .where((s) => name.isNotEmpty && norm(s['name']) == name)
          .toList();
      if (matches.length == 1) await _supplier(matches.single['id']);
      if (matches.isEmpty) await _supplier(_newChoice);
    } catch (e) {
      if (mounted && store == id) setState(() => error = userErrorText(e));
    } finally {
      if (mounted && store == id) setState(() => loadingChoices = false);
    }
  }

  Future<void> _supplier(String id) async {
    setState(() {
      supplier = id;
      periodsLoaded = false;
      period = null;
      periods = [];
      error = null;
      loadingChoices = true;
    });
    try {
      if (id == _newChoice) {
        setState(() {
          period = _newChoice;
          periodsLoaded = true;
        });
        return;
      }
      final list = records(
        await api.get(
          '/api/periods?store_id=${part(store)}&supplier_id=${part(id)}',
        ),
        'periods',
      );
      if (!mounted || supplier != id) return;
      final date = proposedDate(object(preview?['draft']));
      final matches = list
          .where(
            (p) =>
                date != null &&
                date.compareTo('${p['period_start']}') >= 0 &&
                date.compareTo('${p['period_end']}') <= 0,
          )
          .toList();
      final keepPeriod = kept('period_id');
      setState(() {
        periods = list;
        periodsLoaded = true;
        if (matches.isEmpty) period = _newChoice;
        if (matches.length == 1) period = matches.single['period_id'];
        if (keepPeriod != null && list.any((p) => '${p['period_id']}' == keepPeriod)) {
          period = keepPeriod;
        }
      });
    } catch (e) {
      if (mounted && supplier == id) setState(() => error = userErrorText(e));
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
    final entered = tradeDate.trim();
    final parsed = DateTime.tryParse(entered);
    if (entered.isNotEmpty && (parsed == null || day(parsed) != entered)) {
      setState(() => error = '거래일을 연도-월-일 형식으로 확인해 주세요.');
      return;
    }
    final overrides = <String, int?>{};
    final draft = object(preview?['draft']);
    for (final entry in amountInputs.entries) {
      final text = entry.value.trim();
      final amount = int.tryParse(text);
      if (text.isNotEmpty && (!RegExp(r'^-?[0-9]+$').hasMatch(text) ||
          amount == null || amount.abs() > 9007199254740991)) {
        setState(() => error = '${statementAmountLabels[entry.key]}을 원 단위 정수로 입력해 주세요.');
        return;
      }
      if (amount != draft[entry.key]) overrides[entry.key] = amount;
    }
    final edits = <Json>[];
    for (final l in lines) {
      String? val(String k) {
        final t = l[k]?.toString().trim() ?? '';
        return t.isEmpty ? null : t;
      }

      final amounts = {
        for (final key in [
          'amount_read',
          'tax_amount_read',
          'supply_amount_read',
          'discount_amount_read',
          'line_total_read',
        ]) key: val(key),
      };
      final integer = RegExp(r'^-?\d{1,16}$');
      final decimal = RegExp(r'^-?\d{1,16}(\.\d{1,8})?$');
      if (val('item') == null ||
          [
            val('qty_read'),
            val('unit_price_read'),
          ].any((v) => v != null && !decimal.hasMatch(v)) ||
          amounts.values.any((v) =>
              v != null &&
              (!integer.hasMatch(v) || int.parse(v).abs() > 9007199254740991))) {
        setState(() => error = '품목명과 숫자 형식을 확인해 주세요. 모르는 수량·가격은 비워 둘 수 있습니다.');
        return;
      }
      edits.add({
        'item': val('item'),
        'unit': val('unit'),
        'qty_read': val('qty_read'),
        'unit_price_read': val('unit_price_read'),
        for (final key in ['spec', 'item_code', 'origin', 'lot_no', 'line_note'])
          key: val(key),
        for (final entry in amounts.entries)
          entry.key: entry.value == null ? null : int.parse(entry.value!),
      });
    }
    final payload = jsonEncode({
      if (store == _newChoice)
        'store_name': shopName.trim()
      else
        'store_id': store,
      if (supplier == _newChoice)
        'supplier_name': vendorName.trim()
      else
        'supplier_id': supplier,
      if (period == _newChoice)
        'week_start': day(week!)
      else
        'period_id': period,
      if (entered != (object(preview?['draft'])['trade_date'] ?? ''))
        'trade_date': entered.isEmpty ? null : entered,
      if (overrides.isNotEmpty) 'statement_amounts': overrides,
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
        'store': store == _newChoice
            ? shopName.trim()
            : stores.firstWhere((s) => s['id'] == store)['name'],
        'supplier': supplier == _newChoice
            ? vendorName.trim()
            : suppliers.firstWhere((s) => s['id'] == supplier)['name'],
      };
      final savedPeriod = (result['period_id'] ?? period) as String;
      refreshPeriod(ref, savedPeriod);
      Navigator.pop(
        context,
        '${uploadRoute(savedPeriod)}?document=${part(result['document_id'])}',
      );
    } catch (e) {
      if (mounted) setState(() => error = userErrorText(e));
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
          if (draft['source_date_text'] != null) Text('원본 날짜 표기 · ${draft['source_date_text']}'),
          if (draft['doc_date'] != null) Text('문서일 · ${draft['doc_date']}'),
          if (draft['issued_on'] != null) Text('작성·발행일 · ${draft['issued_on']}'),
          if (draft['quoted_on'] != null) Text('견적일 · ${draft['quoted_on']}'),
          TextFormField(initialValue: tradeDate, enabled: !saving,
            decoration: const InputDecoration(labelText: '원본 거래일', hintText: 'YYYY-MM-DD', helperText: '거래일이 없으면 비워 두세요. 정산 기간은 별도로 선택합니다.'),
            onChanged: (value) => tradeDate = value),
          if (amountInputs.isNotEmpty)
            ExpansionTile(title: const Text('원본 명세표 금액'),
              initiallyExpanded: amountInputs.values.any((v) => v.isNotEmpty),
              children: [
                for (final key in amountInputs.keys)
                  TextFormField(initialValue: amountInputs[key], enabled: !saving,
                    decoration: InputDecoration(labelText: '${statementAmountLabels[key]} (원)', hintText: '미기재'),
                    onChanged: (v) => amountInputs[key] = v),
              ]),
          if (!storesLoaded && !loadingChoices)
            TextButton(
              onPressed: _loadStores,
              child: const Text('점포 목록 다시 불러오기'),
            ),
          if (storesLoaded && store == null && !loadingChoices) ...[
            Text(shopName.trim().isEmpty
                ? '공급받는 점포 이름을 확인해 주세요.'
                : '사진의 공급받는 곳은 ‘$shopName’입니다. 저장할 점포를 선택해 주세요.'),
            if (shopName.trim().isNotEmpty && !stores.any((s) =>
                s['name']?.toString().trim().toLowerCase() == shopName.trim().toLowerCase()))
              OutlinedButton(onPressed: () => _store(_newChoice),
                child: const Text('이 이름으로 새 점포 등록하기')),
          ],
          _choice(
              '내 점포',
              store,
              {
                if (storesLoaded) _newChoice: '새 점포 등록',
                for (final s in stores) '${s['id']}': '${s['name']}',
              },
              _store),
          if (store == _newChoice)
            TextFormField(
                initialValue: shopName,
                enabled: !saving,
                maxLength: 150,
                decoration:
                    const InputDecoration(labelText: '내 점포 이름 (공급받는 곳)'),
                onChanged: (v) => setState(() => shopName = v)),
          _choice(
              '저장할 거래처',
              supplier,
              {
                if (suppliersLoaded) _newChoice: '새 거래처 등록',
                for (final s in suppliers) '${s['id']}': '${s['name']}',
              },
              _supplier),
          if (supplier == _newChoice)
            TextFormField(
                initialValue: vendorName,
                enabled: !saving,
                maxLength: 150,
                decoration: const InputDecoration(labelText: '새 거래처 이름 (공급자)'),
                onChanged: (v) => setState(() => vendorName = v)),
          _choice(
              '정산 기간',
              period,
              {
                if (periodsLoaded) _newChoice: '새 정산 주',
                for (final p in periods) '${p['period_id']}': '${p['label']}',
              },
              (v) => setState(() => period = v)),
          _choice(
              '문서 종류',
              type,
              {
                for (final t in photoTypes) t: docTypeText(t),
              },
              (v) => setState(() => type = v)),
          if (period == _newChoice)
            OutlinedButton(
                onPressed: saving ? null : chooseWeek,
                child: Text(week == null
                    ? '자료를 보관할 정산 주 선택'
                    : '${day(week!)} ~ ${day(week!.add(const Duration(days: 6)))} · 주 변경')),
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
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('품목 상세 정보'),
                      children: [
                        _field(l, 'spec', '규격'),
                        _field(l, 'item_code', '품목코드'),
                        _field(l, 'origin', '원산지'),
                        _field(l, 'lot_no', '로트번호'),
                        _field(l, 'supply_amount_read', '공급가액 (원)'),
                        _field(l, 'discount_amount_read', '할인액 (원)'),
                        _field(l, 'tax_amount_read', '세액 (원)'),
                        _field(l, 'line_total_read', '합계금액 (원)'),
                        _field(l, 'line_note', '비고'),
                      ],
                    ),
                    if (l['line_date_text'] != null) Text('품목 날짜 표기 · ${l['line_date_text']}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                reading || saving || !ready || type == null || lines.isEmpty
                    ? null
                    : _save,
            child: Text(saving
                ? '저장 중'
                : store == _newChoice
                    ? '새 점포 등록하고 원본 저장'
                    : supplier == _newChoice
                    ? '거래처 등록하고 원본 저장'
                    : '판독값 확인하고 저장'),
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
  late final PlatformFile file;
  try {
    if ([TargetPlatform.android, TargetPlatform.iOS]
        .contains(defaultTargetPlatform)) {
      final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const Icon(Icons.photo_camera),
                    title: const Text('사진 촬영'),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera)),
                ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('앨범에서 선택'),
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery))
              ])));
      if (source == null) return;
      final photo = await ImagePicker()
          .pickImage(source: source, preferredCameraDevice: CameraDevice.rear);
      if (photo == null) return;
      final length = await photo.length();
      if (length > 10485760) {
        if (context.mounted) notify(context, '10MB 이하의 사진을 선택해 주세요.');
        return;
      }
      final bytes = await photo.readAsBytes();
      final ext = bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8
          ? 'jpg'
          : bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50
              ? 'png'
              : bytes.length >= 12 &&
                      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
                          'WEBP'
                  ? 'webp'
                  : null;
      if (ext == null) {
        if (context.mounted) notify(context, 'PNG·JPEG·WebP 사진을 선택해 주세요.');
        return;
      }
      final name = photo.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      file = PlatformFile(name: '$name.$ext', size: length, bytes: bytes);
    } else {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          withData: true);
      if (picked == null || picked.files.single.bytes == null) return;
      file = picked.files.single;
    }
  } catch (_) {
    if (context.mounted)
      notify(context, '사진을 열 수 없습니다. 카메라 권한을 확인하거나 앨범에서 선택해 주세요.');
    return;
  }
  if (!context.mounted) return;
  if (file.size > 10485760) {
    notify(context, '10MB 이하의 사진을 선택해 주세요.');
    return;
  }
  final route = await Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => PhotoReview(file)));
  if (context.mounted && route != null) context.go(route);
}
