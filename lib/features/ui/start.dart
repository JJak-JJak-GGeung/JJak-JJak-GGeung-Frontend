import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'call_recording.dart';
import 'photo_review.dart';
import 'directory.dart';
import 'shared.dart';

/// Entry screen `/`: the owner picks 점포 → 거래처 → 정산 기간 (no login).
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});
  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  late Future<List<Json>> stores;
  Future<List<Json>>? suppliers;
  Future<List<Json>>? periods;
  bool directoryReady = false;
  Json? store;
  Json? supplier;

  @override
  void initState() {
    super.initState();
    stores = _loadStores();
  }

  Future<List<Json>> _loadStores() async {
    final result = object(await backend.get('/api/stores'));
    final enabled = !demo && result['directory_registration'] == true;
    if (mounted && directoryReady != enabled) setState(() => directoryReady = enabled);
    return records(result, 'stores');
  }

  void _pickStore(Json row) {
    ref.read(pickedNames.notifier).state = {'store': row['name'].toString()};
    setState(() {
      store = row;
      supplier = null;
      periods = null;
      suppliers = backend
          .get('/api/suppliers?store_id=${part(row['id'])}')
          .then((v) => records(v, 'suppliers'));
    });
  }

  void _pickSupplier(Json row) {
    ref.read(pickedNames.notifier).state = {
      'store': store!['name'].toString(),
      'supplier': row['name'].toString(),
    };
    setState(() {
      supplier = row;
      periods = backend
          .get(
            '/api/periods?store_id=${part(store!['id'])}&supplier_id=${part(row['id'])}',
          )
          .then((v) => records(v, 'periods'));
    });
  }

  bool _openingWeek = false;

  /// Week picker: the last eight Monday-to-Sunday weeks. A week without a
  /// period is opened on the server (POST /api/periods) before navigating.
  Future<void> _pickWeek(List<Json> existing) async {
    final byStart = {for (final p in existing) p['period_start']?.toString(): p};
    final week = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _WeekSheet(existingStarts: byStart.keys.whereType<String>().toSet()),
    );
    if (week == null || !mounted) return;
    final start = isoDate(week);
    final known = byStart[start];
    if (known != null) {
      context.go(periodRoute(known['period_id'].toString()));
      return;
    }
    final storeRow = store!, supplierRow = supplier!;
    setState(() => _openingWeek = true);
    try {
      final opened = await backend.post('/api/periods', {
        'store_id': storeRow['id'],
        'supplier_id': supplierRow['id'],
        'week_start': start,
      });
      // Drop the reply if the owner switched 점포 or 거래처 meanwhile, so the
      // period never opens under another supplier's name.
      if (!mounted || !identical(store, storeRow) || !identical(supplier, supplierRow)) return;
      context.go(periodRoute(opened['period_id'].toString()));
    } catch (e) {
      if (mounted) notify(context, e);
    } finally {
      if (mounted) setState(() => _openingWeek = false);
    }
  }

  Future<void> _register({Json? parent}) async {
    final row = await showDialog<Json>(
      context: context, barrierDismissible: false,
      builder: (_) => RegisterNameDialog(api: backend, store: parent),
    );
    if (row == null || !mounted) return;
    if (parent == null) {
      setState(() => stores = _loadStores());
      _pickStore(row);
    } else {
      _pickStore(parent);
      _pickSupplier(row);
    }
    notify(context, row['created'] == true ? '${row['name']} 등록 완료' : '이미 등록된 ${row['name']}을 열었습니다.');
  }

  /// Upload button: the owner chooses a photo or a call recording.
  Future<void> _openAttach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('사진 올리기'),
              subtitle: const Text('명세서·수령 기록·청구서 사진'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('통화녹음 올리기'),
              subtitle: const Text('받아쓴 내용을 거래의 통화 메모로 저장'),
              onTap: () => Navigator.pop(context, 'call'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'photo') await _openUpload();
    if (choice == 'call') await startCallRecording(context);
  }

  /// Photo upload. Connected builds open the photo first; the offline demo
  /// picks store, supplier and period in a sheet, then opens that period's
  /// upload screen.
  Future<void> _openUpload() async {
    if (!demo) {
      await startPhotoReview(context);
      return;
    }
    final target = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _UploadTargetSheet(store: store, supplier: supplier),
    );
    if (target == null || !mounted) return;
    ref.read(pickedNames.notifier).state = {
      'store': target['store']['name'].toString(),
      'supplier': target['supplier']['name'].toString(),
    };
    context.go(uploadRoute(target['period']['period_id'].toString()));
  }

  @override
  Widget build(BuildContext context) => Screen(
    title: '짝짜꿍',
    leading: false,
    appBarActions: [
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 16),
        child: Center(
          child: ClipOval(
            child: Image.asset(
              'assets/service_logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ],
    floatingActionButton: FloatingActionButton(
      onPressed: _openAttach,
      tooltip: '사진·통화녹음 올리기',
      shape: const CircleBorder(),
      backgroundColor: Palette.primary,
      foregroundColor: Colors.white,
      child: const Icon(Icons.add),
    ),
    children: [
      const Text('사진으로 시작하거나 내 점포를 여세요', style: Txt.title),
      const SizedBox(height: 24),
      _Pending(
        future: stores,
        retry: () => setState(() => stores = _loadStores()),
        render: (rows) => _Picker(
          label: '점포',
          rows: rows,
          selected: store,
          empty: directoryReady ? '점포 이름을 입력하거나 사진에서 상호를 확인해 첫 점포를 등록하세요.' : '사진을 올리고 상호를 확인하면 첫 점포를 등록할 수 있어요.',
          onPick: _pickStore,
        ),
      ),
      if (directoryReady)
        TextButton.icon(onPressed: () => _register(), icon: const Icon(Icons.add_business_outlined), label: const Text('점포 직접 등록')),
      if (suppliers != null) ...[
        const SizedBox(height: 16),
        _Pending(
          future: suppliers!,
          retry: () => _pickStore(store!),
          render: (rows) => _Picker(
            key: ValueKey(store?['id']),
            label: '거래처',
            rows: rows,
            selected: supplier,
            empty: '이 점포에 등록된 거래처가 없습니다.',
            onPick: _pickSupplier,
          ),
        ),
      ],
      if (directoryReady && store != null)
        TextButton.icon(onPressed: () => _register(parent: store), icon: const Icon(Icons.add), label: const Text('거래처 직접 등록')),
      if (directoryReady)
        TextButton(onPressed: () => openSampleDelivery(context, backend), child: const Text('예시 명세표로 연습')),
      if (periods != null) ...[
        const SectionTitle(
          '정산 기간',
          caption: '조회할 주를 고르세요. 사진을 확정하면 그 주가 자동으로 생깁니다.',
        ),
        _Pending(
          future: periods!,
          retry: () => _pickSupplier(supplier!),
          render: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const Text('아직 자료가 있는 주가 없습니다. 아래에서 조회할 주를 고르세요.', style: Txt.body)
              else
                ...gap([
                  for (final row in rows)
                    InfoRow(
                      periodText(row),
                      '열기',
                      caption: row['label']?.toString(),
                      onTap: () => context.go(periodRoute(row['period_id'].toString())),
                    ),
                ], 10),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openingWeek ? null : () => _pickWeek(rows),
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_openingWeek ? '여는 중…' : '다른 주 조회'),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Field that opens a bottom sheet listing `{id, name}` rows.
///
/// Replaces the Material dropdown, whose popup covered the field and spanned
/// the whole phone width without the app's rounded card style.
class _Picker extends StatelessWidget {
  const _Picker({
    super.key,
    required this.label,
    required this.rows,
    required this.selected,
    required this.empty,
    required this.onPick,
  });
  final String label;
  final List<Json> rows;
  final Json? selected;
  final String empty;
  final void Function(Json) onPick;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('$label 선택', style: Txt.section),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return _OptionTile(
                      text: row['name'].toString(),
                      selected:
                          row['id']?.toString() == selected?['id']?.toString(),
                      onTap: () => Navigator.pop(context, row),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null &&
        picked['id']?.toString() != selected?['id']?.toString()) {
      onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text(empty, style: Txt.body);
    final name = selected?['name']?.toString();
    return Semantics(
      button: true,
      label: '$label 선택',
      child: Material(
        color: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: name == null ? Palette.line : Palette.primary,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Txt.caption),
                      const SizedBox(height: 2),
                      Text(
                        name ?? '$label를 골라 주세요',
                        overflow: TextOverflow.ellipsis,
                        style: name == null
                            ? Txt.body.copyWith(
                                color: Palette.muted,
                                fontSize: 16,
                              )
                            : Txt.value.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, size: inlineIconSize, color: Palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One selectable card in a choice list (selected: blue border + check).
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.selected,
    required this.onTap,
    this.caption,
  });
  final String text;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Palette.tint : Palette.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: selected ? Palette.primary : Palette.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.value.copyWith(
                      color: selected ? Palette.primary : Palette.ink,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 2),
                    Text(caption!, style: Txt.caption),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: Palette.primary, size: inlineIconSize),
          ],
        ),
      ),
    ),
  );
}

/// Sheet behind the camera button: 점포 → 거래처 → 정산 기간 in one place.
/// Starts from what the start screen already selected and picks a level by
/// itself when it has exactly one option. Pops `{store, supplier, period}`.
class _UploadTargetSheet extends StatefulWidget {
  const _UploadTargetSheet({this.store, this.supplier});
  final Json? store;
  final Json? supplier;

  @override
  State<_UploadTargetSheet> createState() => _UploadTargetSheetState();
}

class _UploadTargetSheetState extends State<_UploadTargetSheet> {
  Json? store;
  Json? supplier;
  Json? period;
  List<Json>? stores;
  List<Json>? suppliers;
  List<Json>? periods;
  Object? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    store = widget.store;
    supplier = widget.store == null ? null : widget.supplier;
    _load();
  }

  /// Loads the next missing list; auto-selects single options.
  /// Bumped on every load; a load whose number is no longer current drops
  /// its results, so a slow answer for an earlier pick never lands under a
  /// later one.
  int _generation = 0;

  Future<void> _load() async {
    final generation = ++_generation;
    bool current() => mounted && generation == _generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (stores == null) {
        final rows = records(await backend.get('/api/stores'), 'stores');
        if (!current()) return;
        stores = rows;
        if (store == null && rows.length == 1) store = rows.first;
      }
      if (store != null && suppliers == null) {
        final rows = records(
          await backend.get('/api/suppliers?store_id=${part(store!['id'])}'),
          'suppliers',
        );
        if (!current()) return;
        suppliers = rows;
        if (supplier == null && rows.length == 1) supplier = rows.first;
      }
      if (store != null && supplier != null && periods == null) {
        final rows = records(
          await backend.get(
            '/api/periods?store_id=${part(store!['id'])}&supplier_id=${part(supplier!['id'])}',
          ),
          'periods',
        );
        if (!current()) return;
        periods = rows;
        if (period == null && rows.isNotEmpty)
          period = rows.first; // newest first
      }
    } catch (e) {
      if (current()) error = e;
    }
    if (current()) setState(() => loading = false);
  }

  void _pickStore(Json row) {
    if (store != null && _key(row) == _key(store!)) return;
    setState(() {
      store = row;
      supplier = null;
      period = null;
      suppliers = null;
      periods = null;
    });
    _load();
  }

  void _pickSupplier(Json row) {
    if (supplier != null && _key(row) == _key(supplier!)) return;
    setState(() {
      supplier = row;
      period = null;
      periods = null;
    });
    _load();
  }

  static String _key(Json row) => (row['period_id'] ?? row['id']).toString();

  List<Widget> _section(
    String title,
    List<Json>? rows,
    Json? selected,
    String Function(Json) text,
    void Function(Json) onPick, {
    String Function(Json)? caption,
    required String empty,
  }) => [
    Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: Txt.label),
    ),
    if (rows != null && rows.isEmpty)
      Text(empty, style: Txt.body)
    else if (rows != null)
      ...gap([
        for (final row in rows)
          _OptionTile(
            text: text(row),
            caption: caption?.call(row),
            selected: selected != null && _key(row) == _key(selected),
            onTap: () => onPick(row),
          ),
      ], 8),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('사진 올리기', style: Txt.section),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '사진은 한 정산 기간에 묶어 저장합니다. 올릴 정산을 확인해 주세요.',
              style: Txt.label,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                ..._section(
                  '점포',
                  stores,
                  store,
                  (r) => r['name'].toString(),
                  _pickStore,
                  empty: '사진을 올리고 상호를 확인하면 첫 점포를 등록할 수 있어요.',
                ),
                if (store != null)
                  ..._section(
                    '거래처',
                    suppliers,
                    supplier,
                    (r) => r['name'].toString(),
                    _pickSupplier,
                    empty: '이 점포에 등록된 거래처가 없습니다.',
                  ),
                if (supplier != null)
                  ..._section(
                    '정산 기간',
                    periods,
                    period,
                    periodText,
                    (r) => setState(() => period = r),
                    caption: (r) => r['label']?.toString() ?? '',
                    empty: '조회할 정산 기간이 없습니다.',
                  ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(userErrorText(error), style: Txt.body),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('다시 불러오기'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton.icon(
              onPressed:
                  loading || store == null || supplier == null || period == null
                  ? null
                  : () => Navigator.pop(context, {
                      'store': store,
                      'supplier': supplier,
                      'period': period,
                    }),
              icon: const Icon(Icons.photo_camera),
              label: const Text('이 정산에 사진 올리기'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// `2026-11-09`
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lists the current week and the seven before it (Monday starts).
class _WeekSheet extends StatelessWidget {
  const _WeekSheet({required this.existingStarts});
  final Set<String> existingStarts;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weeks = [for (var i = 0; i < 8; i++) monday.subtract(Duration(days: 7 * i))];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('조회할 주 선택', style: Txt.section),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('월요일부터 일요일까지 한 주씩 정산합니다.', style: Txt.label),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: weeks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final start = weeks[i];
                final end = start.add(const Duration(days: 6));
                final has = existingStarts.contains(isoDate(start));
                return _OptionTile(
                  text: periodText({'period_start': isoDate(start), 'period_end': isoDate(end)}),
                  caption: [if (i == 0) '이번 주', has ? '자료 있음' : '새로 열기'].join(' · '),
                  selected: has,
                  onTap: () => Navigator.pop(context, start),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Loading / error wrapper for a one-off request.
class _Pending extends StatelessWidget {
  const _Pending({required this.future, required this.render, this.retry});
  final Future<List<Json>> future;
  final Widget Function(List<Json>) render;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: future,
    builder: (context, state) {
      // A new future keeps the previous snapshot's data/error until it
      // completes, so check the connection state first.
      if (state.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (state.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(userErrorText(state.error), style: Txt.body),
            if (retry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: retry, child: const Text('다시 불러오기')),
            ],
          ],
        );
      }
      return render(state.data ?? const []);
    },
  );
}
