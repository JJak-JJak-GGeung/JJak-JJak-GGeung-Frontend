import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'recording_io.dart' if (dart.library.js_interop) 'recording_web.dart';

const base = String.fromEnvironment('API_BASE_URL');
const demo = base == '';
SupabaseClient? auth;
final api = SettlementApi(base, () => auth?.auth.currentSession?.accessToken);
final sample = <String, dynamic>{
  'summary': {
    'billed_qty': '100',
    'received_qty': '96',
    'unit': 'kg',
    'billed_amount': 2000000
  },
  'items': [
    {
      'transaction_id': 'sample-delivery',
      'delivery_no': 'DL-A131',
      'delivery_date': '2026-11-13',
      'declared_qty': '40',
      'billed_qty': '40',
      'received_qty': '36',
      'unit': 'kg',
      'check_amount': 80000,
    }
  ],
};
final settlement = FutureProvider.family<Json, String>((ref, id) async =>
    demo ? sample : object(await api.get('/api/periods/' + part(id))));
final periods = FutureProvider<List<Json>>((ref) async => demo
    ? [
        {'period_id': 'sample', 'label': '공개 A 예시'}
      ]
    : records(await api.get('/api/periods'), 'periods'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (!demo && url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    auth = Supabase.instance.client;
  }
  runApp(const ProviderScope(child: App()));
}

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const Home(), routes: [
    GoRoute(
        path: 'period/:p',
        builder: (_, s) => SettlementPage(s.pathParameters['p']!),
        routes: [
          GoRoute(
              path: 'transaction/:t',
              builder: (_, s) => TransactionPage(
                  s.pathParameters['p']!, s.pathParameters['t']!)),
          GoRoute(
              path: 'approvals',
              builder: (_, s) => Approvals(s.pathParameters['p']!)),
        ]),
    GoRoute(
        path: 'approval/:s',
        builder: (_, s) => Approval(s.pathParameters['s']!)),
  ]),
]);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: '짝짜꿍',
        routerConfig: router,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff2458ce),
          scaffoldBackgroundColor: const Color(0xfff6f8fc),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
          useMaterial3: true,
        ),
      );
}

class Page extends StatelessWidget {
  const Page(this.title, this.child, {super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    if (demo)
                      const Center(child: Chip(label: Text('공개 A 예시 응답'))),
                    child,
                  ]),
                ))),
      );
}

Widget loaded<T>(AsyncValue<T> value, Widget Function(T) render) => value.when(
    skipLoadingOnRefresh: false,
    data: render,
    error: (e, _) => Text(e.toString()),
    loading: () => const Center(child: CircularProgressIndicator()));
Widget pending<T>(Future<T> future, Widget Function(T) render) =>
    FutureBuilder<T>(
        future: future,
        builder: (_, state) {
          if (state.hasError) return Text(state.error.toString());
          if (!state.hasData)
            return const Center(child: CircularProgressIndicator());
          return render(state.data as T);
        });

String qty(Json row, String field) => row[field] == null
    ? '미확인'
    : row[field].toString() + (row['unit'] ?? '').toString();
String won(Object? v) => v == null
    ? '—'
    : v
            .toString()
            .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') +
        '원';
String path(String p) => '/api/periods/' + part(p);
String route(String p) => '/period/' + part(p);

void notify(BuildContext context, Object e) {
  if (context.mounted)
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
}

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _Home();
}

class _Home extends ConsumerState<Home> {
  String? storeId;
  String? supplierId;
  late Future<List<Json>> stores;
  Future<List<Json>>? suppliers;
  Future<List<Json>>? availablePeriods;

  @override
  void initState() {
    super.initState();
    stores = api.get('/api/stores').then((v) => records(v, 'stores'));
  }

  @override
  Widget build(BuildContext context) => Page(
    '주간 정산',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pending(stores, (rows) => DropdownButtonFormField<String>(
        initialValue: storeId,
        decoration: const InputDecoration(labelText: '점포'),
        items: rows.map((r) => DropdownMenuItem<String>(
          value: r['id'].toString(), child: Text(r['name'].toString()))).toList(),
        onChanged: (id) => setState(() {
          storeId = id;
          supplierId = null;
          availablePeriods = null;
          suppliers = api.get('/api/suppliers?store_id=' + part(id))
            .then((v) => records(v, 'suppliers'));
        }),
      )),
      const SizedBox(height: 16),
      if (suppliers != null) pending(suppliers!, (rows) => DropdownButtonFormField<String>(
        key: ValueKey(storeId),
        initialValue: supplierId,
        decoration: const InputDecoration(labelText: '거래처'),
        items: rows.map((r) => DropdownMenuItem<String>(
          value: r['id'].toString(), child: Text(r['name'].toString()))).toList(),
        onChanged: (id) => setState(() {
          supplierId = id;
          availablePeriods = api.get('/api/periods?store_id=' + part(storeId)
            + '&supplier_id=' + part(id)).then((v) => records(v, 'periods'));
        }),
      )),
      const SizedBox(height: 16),
      if (availablePeriods != null) pending(availablePeriods!, (rows) => Column(
        children: [
          if (rows.isEmpty) const Text('조회할 정산 기간이 없습니다.'),
          for (final row in rows) ListTile(
            title: Text(row['label'].toString()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(route(row['period_id'].toString())),
          ),
        ],
      )),
    ]),
  );
}

class SettlementPage extends ConsumerStatefulWidget {
  const SettlementPage(this.id, {super.key});
  final String id;
  @override
  ConsumerState<SettlementPage> createState() => _SettlementPage();
}

class _SettlementPage extends ConsumerState<SettlementPage> {
  bool busy = false;
  String type = 'DELIVERY';
  String? approvalKey;
  Object? approvalRevision;
  Json uploaded = {};
  final invoices = <Json>[];
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiError && e.status == 409) {
        approvalKey = null;
        ref.invalidate(settlement(widget.id));
      }
      notify(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    final chosen = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true);
    if (chosen == null || !mounted) return;
    final file = chosen.files.single;
    final mime = switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    final value = await api.upload(path(widget.id) + '/documents', file.bytes!,
        file.name, mime, {'doc_type': type, 'request_key': requestKey()});
    if (!mounted) return;
    setState(() {
      uploaded = {'doc_type': type, ...value};
      if (uploaded['doc_type'] == 'INVOICE' &&
          uploaded['document_id'] != null &&
          !invoices.any((doc) => doc['document_id'] == uploaded['document_id']))
        invoices.add(uploaded);
    });
    ref.invalidate(settlement(widget.id));
  }

  Future<void> correctLine(Json row, Object revision) async {
    final quantity = TextEditingController(text: (row['qty_corrected'] ?? row['qty_read'] ?? '').toString());
    final price = TextEditingController(text: (row['unit_price_corrected'] ?? row['unit_price_read'] ?? '').toString());
    final amount = TextEditingController(text: (row['amount_corrected'] ?? row['amount_read'] ?? '').toString());
    final fields = await showDialog<Json>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('원본과 대조해 판독값 정정'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: quantity, decoration: const InputDecoration(labelText: '수량')),
        TextField(controller: price, decoration: const InputDecoration(labelText: '단가')),
        TextField(controller: amount, decoration: const InputDecoration(labelText: '금액')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(dialog, <String, dynamic>{
          if (quantity.text.trim().isNotEmpty) 'qty_corrected': quantity.text.trim(),
          if (price.text.trim().isNotEmpty) 'unit_price_corrected': price.text.trim(),
          if (amount.text.trim().isNotEmpty) 'amount_corrected': amount.text.trim(),
        }), child: const Text('확인 저장')),
      ],
    ));
    quantity.dispose();
    price.dispose();
    amount.dispose();
    if (fields == null || fields.isEmpty || !mounted) return;
    await confirm({
      'kind': 'line_correction', 'source_line_id': row['line_id'],
      'corrected_fields': fields, 'evidence_refs': [source(row)],
    }, revision);
  }

  Future<void> confirm(Json fields, Object? revision) async {
    await api.post(path(widget.id) + '/confirmations', {
      ...fields,
      'expected_revision': revision,
      'request_key': requestKey()
    });
    if (mounted) ref.invalidate(settlement(widget.id));
  }

  @override
  Widget build(BuildContext context) => Page(
      '주간 정산',
      loaded(ref.watch(settlement(widget.id)), (data) {
        final summary = object(data['summary']);
        final items = objects(data['items']);
        final revision = data['input_revision'];
        final approvalList = route(widget.id) + '/approvals';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xffeaf0fd),
                child: ListTile(
                  title: const Text('이번 주 청구액'),
                  subtitle: Text('청구 ' +
                      qty(summary, 'billed_qty') +
                      ' · 수령 ' +
                      qty(summary, 'received_qty')),
                  trailing: Text(won(summary['billed_amount']),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              const SizedBox(height: 16),
              Text('확인할 납품', style: Theme.of(context).textTheme.titleMedium),
              for (final row in items)
                Card(
                    child: ListTile(
                  title: Text([row['delivery_date'], row['delivery_no']]
                      .whereType<String>()
                      .join(' · ')),
                  subtitle: Text('청구 ' +
                      qty(row, 'billed_qty') +
                      ' · 수령 ' +
                      qty(row, 'received_qty')),
                  trailing: Text(won(row['check_amount'])),
                  onTap: () => context.go(route(widget.id) +
                      '/transaction/' +
                      part(row['transaction_id'])),
                )),
              if (!demo) ...[
                DropdownButton<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'DELIVERY', child: Text('납품명세')),
                      DropdownMenuItem(value: 'RECEIPT', child: Text('수령 기록')),
                      DropdownMenuItem(value: 'INVOICE', child: Text('청구서')),
                      DropdownMenuItem(
                          value: 'CORRECTED_INVOICE', child: Text('수정 청구서')),
                    ],
                    onChanged:
                        busy ? null : (value) => setState(() => type = value!)),
                FilledButton.tonal(
                    onPressed: busy ? null : () => run(upload),
                    child: const Text('사진 올리기')),
                for (final doc in objects(data['documents']))
                  if (doc['source_mode'] == 'FILE') ListTile(
                    title: Text((doc['filename'] ?? '원본').toString()),
                    subtitle: Text((doc['doc_type'] ?? '').toString()),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: '원본 열기',
                        icon: const Icon(Icons.image_outlined),
                        onPressed: () => original(context, doc)),
                      if (doc['extraction_status'] != 'COMPLETED' && doc['extraction_status'] != 'SUCCESS')
                        IconButton(
                          tooltip: '판독 다시 시도',
                          icon: const Icon(Icons.refresh),
                          onPressed: busy ? null : () => run(() async {
                            final read = object(await api.post('/api/documents/' + part(doc['document_id']) + '/extraction', {}));
                            if (mounted) setState(() => uploaded = read);
                            ref.invalidate(settlement(widget.id));
                          })),
                      if (doc['extraction_status'] == 'COMPLETED' || doc['extraction_status'] == 'SUCCESS')
                        TextButton(
                          onPressed: busy ? null : () => setState(() => uploaded = doc),
                          child: const Text('확인 작업')),
                    ]),
                    onTap: () => original(context, doc),
                  ),
                if (uploaded['document_id'] != null) ...[
                  Text(uploaded['duplicate'] == true ? '이미 저장된 파일입니다.' : '원본 저장 완료'),
                  TextButton(
                    onPressed: () => original(context, uploaded),
                    child: const Text('저장한 원본 열기')),

                  Text('판독 상태 ' +
                      (uploaded['extraction_status'] ?? '—').toString()),
                  for (final row in objects(uploaded['lines']))
                    ListTile(
                        title: Text((row['delivery_no'] ?? '').toString() +
                            ' · ' +
                            qty(row, 'qty_read')),
                        trailing: TextButton(
                          onPressed: busy || revision == null ? null : () => run(() => correctLine(row, revision)),
                          child: const Text('판독값 정정')),
                        onTap: () => original(context, source(row))),
                  if (uploaded['doc_type'] == 'RECEIPT')
                    for (final row in objects(uploaded['lines']))
                      if (row['line_id'] != null)
                        OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                      final target = await select(
                                          context,
                                          '연결할 납품 행',
                                          items,
                                          deliveryId,
                                          'delivery_no');
                                      if (target != null)
                                        await confirm({
                                          'kind': 'receipt_link',
                                          'source_line_id': row['line_id'],
                                          'target_id': target,
                                          'evidence_refs': [source(row)],
                                        }, revision);
                                    }),
                            child: Text(
                                (row['delivery_no'] ?? '수령 행').toString() +
                                    ' 연결 확인')),
                  if (uploaded['doc_type'] == 'CORRECTED_INVOICE') ...[
                    Text('대체 대상 ' +
                        (uploaded['replaces_doc_no'] ?? '미확인').toString()),
                    Text('원문 거래처 ' +
                        (uploaded['supplier_name_read'] ?? '미확인').toString()),
                    Text((uploaded['agreement_text'] ?? '양측 확인 문구 미확인')
                        .toString()),
                    OutlinedButton(
                        onPressed: () => original(
                            context,
                            source({
                              'source_location':
                                  uploaded['agreement_source_location']
                            })),
                        child: const Text('수정 청구서 원본')),
                    OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                  final candidates = objects(
                                      uploaded['replacement_candidates']);
                                  final knownInvoices = <Object?, Json>{
                                    for (final doc in invoices)
                                      doc['document_id']: doc,
                                    for (final doc
                                        in objects(data['documents']))
                                      if (doc['doc_type'] == 'INVOICE')
                                        doc['document_id']: doc,
                                  };
                                  final target = await select(
                                      context,
                                      '대체할 청구서',
                                      candidates.isEmpty
                                          ? knownInvoices.values.toList()
                                          : candidates,
                                      (row) => row['document_id'],
                                      'doc_no');
                                  if (target != null)
                                    await confirm({
                                      'kind': 'replacement',
                                      'document_id': uploaded['document_id'],
                                      'target_id': target,
                                      'evidence_refs': [
                                        source({
                                          'source_location': uploaded[
                                              'agreement_source_location']
                                        })
                                      ],
                                    }, revision);
                                }),
                        child: const Text('대체 대상 확인')),
                  ],
                ],
              ],
              if (data['blockers'] is List &&
                  (data['blockers'] as List).isNotEmpty)
                Text('확인 필요 · ' + (data['blockers'] as List).join(', ')),
              Text('승인액 ' + won(data['approved_amount'])),
              if (data['can_approve'] == true &&
                  data['approved_amount'] == null &&
                  revision != null)
                FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                              if (approvalRevision != revision) {
                                approvalRevision = revision;
                                approvalKey = null;
                              }
                              final saved = await api.post(
                                  path(widget.id) + '/approvals', {
                                'expected_revision': revision,
                                'request_key': approvalKey ??= requestKey()
                              });
                              if (!mounted) return;
                              ref.invalidate(settlement(widget.id));
                              ref.invalidate(approvalRows(widget.id));
                              if (saved['approval_id'] != null)
                                context.push(
                                    '/approval/' + part(saved['approval_id']));
                            }),
                    child: Text(won(data['approvable_amount']) + ' 직접 승인')),
              TextButton(
                  onPressed: () => context.go(approvalList),
                  child: const Text('승인 내역')),
            ]);
      }));

  Json source(Json row) => {
        'document_id': uploaded['document_id'],
        'line_id': row['line_id'],
        'source_location': row['source_location'],
        'kind': uploaded['doc_type'],
      };
}

Object? deliveryId(Json row) {
  for (final source in objects(row['evidence_refs'])) {
    if (source['kind'] == 'DELIVERY') return source['line_id'];
  }
  return null;
}

Future<Object?> select(BuildContext context, String title, List<Json> rows,
        Object? Function(Json) id, String label) =>
    showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(title: Text(title), children: [
        if (!rows.any((row) => id(row) != null))
          const Padding(
              padding: EdgeInsets.all(16), child: Text('확인할 후보가 없습니다.')),
        for (final row in rows)
          if (id(row) != null)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id(row)),
                child: Text((row[label] ?? id(row)).toString())),
      ]),
    );

Future<void> original(BuildContext context, Json row) {
  final loc = object(row['source_location']);
  final bytes = api.original(row['document_id'].toString());
  return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text('원본 · ' +
                (loc['page'] ?? '—').toString() +
                '쪽 ' +
                (loc['row'] ?? '—').toString() +
                '행'),
            content: SizedBox(
                width: 700,
                height: 420,
                child: pending<Uint8List>(bytes,
                    (value) => InteractiveViewer(child: Image.memory(value)))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'))
            ],
          ));
}

Widget sources(BuildContext context, Json row) => Wrap(spacing: 8, children: [
      for (final source in objects(row['evidence_refs']))
        if (source['document_id'] != null)
          OutlinedButton(
              onPressed: () => original(context, source),
              child: Text(switch (source['kind']) {
                'DELIVERY' => '명세 원본',
                'RECEIPT' => '수령 원본',
                'INVOICE' => '청구 원본',
                'CORRECTED_INVOICE' => '수정 청구 원본',
                _ => '원본',
              })),
    ]);

class TransactionPage extends ConsumerStatefulWidget {
  const TransactionPage(this.periodId, this.id, {super.key});
  final String periodId;
  final String id;
  @override
  ConsumerState<TransactionPage> createState() => _TransactionPage();
}

class _TransactionPage extends ConsumerState<TransactionPage> {
  final memo = TextEditingController();
  final recorder = AudioRecorder();
  late Future<dynamic> detail;
  bool recording = false;
  bool busy = false;
  bool voice = false;
  String? memoKey;
  String get endpoint => '/api/transactions/' + part(widget.id);
  @override
  void initState() {
    super.initState();
    detail = demo ? Future.value(<String, dynamic>{}) : api.get(endpoint);
  }

  @override
  void dispose() {
    memo.dispose();
    recorder.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiError && e.status == 409) {
        memoKey = null;
        refresh();
      }
      notify(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void refresh() {
    ref.invalidate(settlement(widget.periodId));
    setState(() => detail = api.get(endpoint));
  }

  Future<void> microphone() async {
    if (!recording) {
      if (!await recorder.hasPermission()) {
        if (mounted) notify(context, '마이크 권한이 꺼져 있습니다. 직접 입력할 수 있습니다.');
        return;
      }
      final opus =
          kIsWeb && await recorder.isEncoderSupported(AudioEncoder.opus);
      await recorder.start(
          RecordConfig(encoder: opus ? AudioEncoder.opus : AudioEncoder.wav),
          path: await recordingPath(opus ? 'memo.webm' : 'memo.wav'));
      if (mounted) setState(() => recording = true);
      return;
    }
    final url = await recorder.stop();
    if (!mounted) return;
    setState(() => recording = false);
    if (url == null) return;
    final (bytes: bytes, mime: mime) = await readRecording(url);
    if (bytes.isEmpty) throw StateError('녹음 파일 읽기 실패');
    final extension = mime == 'audio/wav'
        ? 'wav'
        : mime == 'audio/ogg'
            ? 'ogg'
            : 'webm';
    final response = await api.upload(
        '/api/transcriptions', bytes, 'memo.' + extension, mime);
    if (!mounted) return;
    setState(() {
      memo.text = (response['draft_text'] ?? '').toString();
      voice = true;
      memoKey = null;
    });
  }

  Future<void> receipt(Json row, Object revision, [Json? previous]) async {
    final input = await receiptForm(context, previous);
    if (input == null) return;
    await api.post(path(widget.periodId) + '/confirmations', {
      'kind': previous == null ? 'receipt_entry' : 'line_correction',
      'target_id': deliveryId(row),
      'expected_revision': revision,
      'request_key': requestKey(),
      'evidence_text': input['evidence_text'],
      if (previous == null) ...{
        'received_qty': input['received_qty'],
        'unit': input['unit']
      } else ...{
        'supersedes_receipt_id': previous['receipt_id'],
        'corrected_fields': {
          'received_qty': input['received_qty'],
          'unit': input['unit']
        }
      },
    });
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => Page(
      '거래 상세',
      loaded(ref.watch(settlement(widget.periodId)), (data) {
        final row = objects(data['items']).firstWhere(
            (r) => r['transaction_id'] == widget.id,
            orElse: () => {});
        final revision = data['input_revision'];
        return FutureBuilder<dynamic>(
            future: detail,
            builder: (context, snapshot) {
              final current = {...row, ...object(snapshot.data)};
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text((current['delivery_no'] ?? widget.id).toString(),
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('명세 ' +
                        qty(current, 'declared_qty') +
                        ' · 청구 ' +
                        qty(current, 'billed_qty') +
                        ' · 수령 ' +
                        qty(current, 'received_qty')),
                    Text('확인할 차이 ' + won(current['check_amount'])),
                    if (data['work_status'] == 'WAITING_REPLY')
                      const Text('확인 중'),
                    sources(context, current),
                    if (snapshot.hasError) Text(snapshot.error.toString()),
                    for (final entry in objects(current['memos']))
                      ListTile(
                          title:
                              Text((entry['confirmed_text'] ?? '').toString()),
                          subtitle: Text(entry['source_mode'] == 'VOICE_MEMO'
                              ? '음성'
                              : '직접 입력')),
                    if (!demo) ...[
                      const Text('수령 확인은 주간 정산의 수령 기록 원본에서 진행해 주세요.'),
                      TextField(
                          controller: memo,
                          onChanged: (_) => memoKey = null,
                          decoration: const InputDecoration(labelText: '통화 메모'),
                          maxLines: 3),
                      OutlinedButton(
                          onPressed: busy ? null : () => run(microphone),
                          child: Text(recording ? '녹음 종료 및 받아쓰기' : '말로 남기기')),
                      FilledButton(
                          onPressed: busy || recording || revision == null
                              ? null
                              : () => run(() async {
                                    final text = memo.text.trim();
                                    if (text.isEmpty) return;
                                    await api.post(endpoint + '/memos', {
                                      'confirmed_text': text,
                                      'source_mode':
                                          voice ? 'VOICE_MEMO' : 'TYPED_TEXT',
                                      'expected_revision': revision,
                                      'request_key': memoKey ??= requestKey(),
                                    });
                                    if (!mounted) return;
                                    memo.clear();
                                    voice = false;
                                    memoKey = null;
                                    refresh();
                                  }),
                          child: const Text('확인 저장')),
                    ],
                  ]);
            });
      }));
}

Future<Json?> receiptForm(BuildContext context, Json? previous) async {
  var number = (previous?['received_qty'] ?? '').toString();
  var unit = (previous?['unit'] ?? '').toString();
  var reason = '';
  final form = GlobalKey<FormState>();
  return showDialog<Json>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(previous == null ? '수령 근거 입력' : '수령 근거 정정'),
            content: Form(
                key: form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      initialValue: number,
                      onChanged: (v) => number = v.trim(),
                      decoration: const InputDecoration(labelText: '수량'),
                      validator: (_) =>
                          RegExp(r'^\d+(\.\d+)?$').hasMatch(number)
                              ? null
                              : '수량을 입력하세요.'),
                  TextFormField(
                      initialValue: unit,
                      onChanged: (v) => unit = v.trim(),
                      decoration: const InputDecoration(labelText: '단위'),
                      validator: (_) => unit.isEmpty ? '단위를 입력하세요.' : null),
                  TextFormField(
                      onChanged: (v) => reason = v.trim(),
                      decoration: const InputDecoration(labelText: '확인 근거'),
                      validator: (_) => reason.isEmpty ? '근거를 입력하세요.' : null),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate())
                      Navigator.pop(context, {
                        'received_qty': number,
                        'unit': unit,
                        'evidence_text': reason
                      });
                  },
                  child: const Text('확인')),
            ],
          ));
}

final approvalRows = FutureProvider.family<List<Json>, String>((ref,
        id) async =>
    demo ? [] : records(await api.get(path(id) + '/approvals'), 'approvals'));
final approvalDetail = FutureProvider.family<Json, String>(
    (ref, id) async => object(await api.get('/api/approvals/' + part(id))));

class Approvals extends ConsumerWidget {
  const Approvals(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Page(
      '승인 내역',
      loaded(
          ref.watch(approvalRows(id)),
          (rows) => Column(children: [
                if (rows.isEmpty) const Text('저장된 승인본이 없습니다.'),
                for (final row in rows)
                  ListTile(
                      title: Text(won(row['approved_amount'])),
                      subtitle: Text(row['approval_id'].toString()),
                      onTap: row['approval_id'] == null
                          ? null
                          : () => context
                              .push('/approval/' + part(row['approval_id']))),
              ])));
}

class Approval extends ConsumerWidget {
  const Approval(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Page(
      '승인본 상세',
      loaded(ref.watch(approvalDetail(id)), (data) {
        final info = {...data, ...object(data['snapshot'])};
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(won(info['approved_amount']),
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('승인 ID ' +
                  id +
                  ' · 자료 버전 ' +
                  (info['input_revision'] ?? '—').toString()),
              Text(info['payment_status'] == 'UNCONFIRMED'
                  ? '송금 미확인'
                  : (info['payment_status'] ?? '송금 미확인').toString()),
              sources(context, info),
              for (final row in objects(info['items'])) sources(context, row),
            ]);
      }));
}
