import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  Json? store;
  Json? supplier;

  @override
  void initState() {
    super.initState();
    stores = _loadStores();
  }

  Future<List<Json>> _loadStores() async => records(await backend.get('/api/stores'), 'stores');

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
          .get('/api/periods?store_id=${part(store!['id'])}&supplier_id=${part(row['id'])}')
          .then((v) => records(v, 'periods'));
    });
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: '짝짜꿍',
        leading: false,
        children: [
          const Text('주간 정산을 열 점포를 고르세요', style: Txt.title),
          const SizedBox(height: 8),
          const Text('점포와 거래처를 고르면 그 주의 청구·납품·수령 기록을 함께 봅니다.', style: Txt.label),
          const SizedBox(height: 24),
          _Pending(
            future: stores,
            retry: () => setState(() => stores = _loadStores()),
            render: (rows) => _Picker(
              label: '점포',
              rows: rows,
              selected: store,
              empty: '등록된 점포가 없습니다.',
              onPick: _pickStore,
            ),
          ),
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
          if (periods != null) ...[
            const SectionTitle('정산 기간', caption: '열어 볼 주를 고르세요.'),
            _Pending(
              future: periods!,
              retry: () => _pickSupplier(supplier!),
              render: (rows) => rows.isEmpty
                  ? const Text('조회할 정산 기간이 없습니다.', style: Txt.body)
                  : Column(
                      children: gap([
                        for (final row in rows)
                          InfoRow(
                            periodText(row),
                            '열기',
                            caption: row['label']?.toString(),
                            onTap: () => context.go(periodRoute(row['period_id'].toString())),
                          ),
                      ], 10),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  final on = row['id']?.toString() == selected?['id']?.toString();
                  return Material(
                    color: on ? Palette.tint : Palette.canvas,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: on ? Palette.primary : Palette.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        child: Row(children: [
                          Expanded(
                            child: Text(row['name'].toString(),
                                overflow: TextOverflow.ellipsis,
                                style: Txt.value.copyWith(color: on ? Palette.primary : Palette.ink)),
                          ),
                          if (on) const Icon(Icons.check, color: Palette.primary, size: 20),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (picked != null && picked['id']?.toString() != selected?['id']?.toString()) {
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
          side: BorderSide(color: name == null ? Palette.line : Palette.primary),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: Txt.caption),
                  const SizedBox(height: 2),
                  Text(name ?? '$label를 골라 주세요',
                      overflow: TextOverflow.ellipsis,
                      style: name == null
                          ? Txt.body.copyWith(color: Palette.muted, fontSize: 16)
                          : Txt.value.copyWith(fontSize: 16)),
                ]),
              ),
              const Icon(Icons.expand_more, color: Palette.muted),
            ]),
          ),
        ),
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
                child: Center(child: CircularProgressIndicator()));
          }
          if (state.hasError) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(state.error.toString(), style: Txt.body),
              if (retry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: retry, child: const Text('다시 불러오기')),
              ],
            ]);
          }
          return render(state.data ?? const []);
        },
      );
}
