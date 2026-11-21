import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import 'demo_backend.dart';
import 'start_button.dart';

export '../../api.dart';

// ------------------------------------------------------------------ backend

const apiBase = String.fromEnvironment('API_BASE_URL');

/// True when no server address was given at build time. Screens then read
/// the in-memory [DemoBackend] and show an "예시 응답" banner.
const demo = apiBase == '';

/// Supplies the credential retained by this browser profile.
String? Function() accessToken = () => null;

final DemoBackend? demoBackend = demo ? DemoBackend() : null;
final Backend backend =
    demoBackend ?? SettlementApi(apiBase, () => accessToken());

String periodPath(String p) => '/api/periods/${part(p)}';
String periodRoute(String p) => '/period/${part(p)}';
String transactionRoute(String p, Object? t) =>
    '${periodRoute(p)}/transaction/${part(t)}';
String approveRoute(String p) => '${periodRoute(p)}/approve';
String uploadRoute(String p) => '${periodRoute(p)}/upload';
String approvalsRoute(String p) => '${periodRoute(p)}/approvals';
String approvalRoute(Object? s) => '/approval/${part(s)}';

// ---------------------------------------------------------------- providers

/// Latest settlement for a period: GET /api/periods/P.
final settlementProvider = FutureProvider.autoDispose.family<Json, String>(
    (ref, id) async => object(await backend.get(periodPath(id))));

/// Transaction detail with memos and receipts: GET /api/transactions/T.
final transactionProvider = FutureProvider.autoDispose.family<Json, String>(
    (ref, id) async =>
        object(await backend.get('/api/transactions/${part(id)}')));

/// Approval list of a period: GET /api/periods/P/approvals.
final approvalsProvider = FutureProvider.autoDispose.family<List<Json>, String>(
    (ref, id) async =>
        records(await backend.get('${periodPath(id)}/approvals'), 'approvals'));

/// One approval as stored at approval time: GET /api/approvals/S.
final approvalProvider = FutureProvider.autoDispose.family<Json, String>(
    (ref, id) async => object(await backend.get('/api/approvals/${part(id)}')));

/// Store and supplier names picked on the start screen, used when the
/// period response does not carry names.
final pickedNames = StateProvider<Map<String, String>>((ref) => {});

/// Reloads everything that depends on a period after a change was saved.
void refreshPeriod(WidgetRef ref, String periodId) {
  ref.invalidate(settlementProvider(periodId));
  ref.invalidate(approvalsProvider(periodId));
  ref.invalidate(transactionProvider);
}

// ------------------------------------------------------------------- tokens

/// Colors taken from the Figma final SVG.
abstract final class Palette {
  static const primary = Color(0xff2458ce);
  static const ink = Color(0xff172538);
  static const muted = Color(0xff526176);
  static const line = Color(0xffd1d9e6);
  static const canvas = Color(0xfff5f6f9);
  static const surface = Color(0xffffffff);
  static const tint = Color(0xffedf3ff);
  static const warnBg = Color(0xfffff0dc);
  static const warnInk = Color(0xff91450d);
  static const okBg = Color(0xffe3f4ea);
  static const okInk = Color(0xff1d6b3f);
  static const infoBg = Color(0xffe8eef9);
  static const infoInk = Color(0xff2a4a8a);
  static const errBg = Color(0xfffde8e8);
  static const errInk = Color(0xffa22b2b);
}

/// Bundled Korean font (pubspec `fonts`). Component themes that set their own
/// TextStyle must name it too, or they fall back to browser-fetched fonts.
const appFont = 'NanumGothic';

ThemeData appTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.primary,
          primary: Palette.primary,
          surface: Palette.surface),
      scaffoldBackgroundColor: Palette.canvas,
      // Bundled NanumGothic (assets/fonts) so Korean never renders as tofu
      // while the browser fetches fallback fonts. Bold covers w600–w900.
      fontFamily: appFont,
      fontFamilyFallback: const ['Noto Sans KR', 'Apple SD Gothic Neo', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: Palette.surface,
        foregroundColor: Palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: appFont,
            fontSize: 21, fontWeight: FontWeight.w700, color: Palette.ink),
        shape: Border(bottom: BorderSide(color: Palette.line)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Palette.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Palette.line)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 17, fontWeight: FontWeight.w700),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: Palette.ink,
        side: const BorderSide(color: Palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w700),
      )),
    );

abstract final class Txt {
  static const title =
      TextStyle(fontFamily: appFont, fontSize: 22, fontWeight: FontWeight.w700, color: Palette.ink);
  static const section =
      TextStyle(fontFamily: appFont, fontSize: 17, fontWeight: FontWeight.w700, color: Palette.ink);
  static const body = TextStyle(fontFamily: appFont, fontSize: 14, color: Palette.ink, height: 1.45);
  static const label = TextStyle(fontFamily: appFont, fontSize: 13, color: Palette.muted);
  static const caption =
      TextStyle(fontFamily: appFont, fontSize: 12, color: Palette.muted, height: 1.4);
  static const value =
      TextStyle(fontFamily: appFont, fontSize: 15, fontWeight: FontWeight.w700, color: Palette.ink);
  static const amount =
      TextStyle(fontFamily: appFont, fontSize: 19, fontWeight: FontWeight.w700, color: Palette.ink);
}

// ------------------------------------------------------------- line breaks

final _hangulPair = RegExp(r'([가-힣ㄱ-ㅎㅏ-ㅣ])(?=[가-힣ㄱ-ㅎㅏ-ㅣ0-9A-Za-z.,!?·%)])');

/// Keeps Korean words whole when text wraps. Flutter may break Hangul between
/// any two syllables ("여/세요"); a WORD JOINER (U+2060) between the letters
/// of a word leaves only spaces as break points, like CSS `word-break:
/// keep-all`. Use it for titles, labels and button text.
String keepWords(String text) => text.replaceAllMapped(_hangulPair, (m) => '${m[1]}\u2060');

// --------------------------------------------------------------- formatting

/// "36kg" or "실입고 미확인" for a null received quantity. A confirmed zero
/// stays "0kg" (R01).
String qtyText(Json row, String field, {String missing = '미확인'}) {
  final value = row[field];
  if (value == null) return missing;
  return '$value${row['unit'] ?? ''}';
}

String receivedText(Json row) =>
    qtyText(row, 'received_qty', missing: '실입고 미확인');

String won(Object? v) => v == null
    ? '—'
    : '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

num? decimal(Object? v) => v == null ? null : num.tryParse(v.toString());

/// Signed difference with direction, e.g. "+4kg" (청구가 많음).
String deltaText(Json row) {
  final d = decimal(row['delta_qty']);
  if (d == null) return '차이 미확인';
  final unit = row['unit'] ?? '';
  if (d == 0) return '0$unit';
  return d > 0 ? '+${row['delta_qty']}$unit' : '${row['delta_qty']}$unit';
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
const _ordinals = ['첫째', '둘째', '셋째', '넷째', '다섯째'];

/// "11/13(금)"
String dayText(Object? isoDate) {
  final d = DateTime.tryParse(isoDate?.toString() ?? '');
  if (d == null) return '날짜 미확인';
  return '${d.month}/${d.day}(${_weekdays[d.weekday - 1]})';
}

/// "11월 둘째 주 · 11/09~11/15"
String periodText(Json data) {
  final start = DateTime.tryParse(data['period_start']?.toString() ?? '');
  final end = DateTime.tryParse(data['period_end']?.toString() ?? '');
  if (start == null) return (data['label'] ?? '정산 기간').toString();
  final week = _ordinals[((start.day + 6) ~/ 7 - 1).clamp(0, 4)];
  final range = end == null
      ? ''
      : ' · ${start.month}/${start.day.toString().padLeft(2, '0')}~${end.month}/${end.day.toString().padLeft(2, '0')}';
  return '${start.month}월 $week 주$range';
}

String supplierName(WidgetRef ref, Json data) =>
    (data['supplier_name'] ?? ref.read(pickedNames)['supplier'] ?? '거래처')
        .toString();

/// Agreed payment date from the period or its current invoice (R09).
String? paymentDue(Json data) {
  final direct = data['payment_due_on'];
  if (direct != null) return direct.toString();
  for (final doc in objects(data['documents']).reversed) {
    if (doc['payment_due_on'] != null &&
        (doc['doc_type'] == 'INVOICE' ||
            doc['doc_type'] == 'CORRECTED_INVOICE')) {
      return doc['payment_due_on'].toString();
    }
  }
  return null;
}

String paymentText(Object? status) => switch (status) {
      'CONFIRMED' || 'PAID' => '송금 확인됨',
      _ => '미확인',
    };

String docTypeText(Object? type) => switch (type) {
      'DELIVERY' => '납품 명세서',
      'RECEIPT' => '점포 수령 기록',
      'INVOICE' => '청구서',
      'CORRECTED_INVOICE' => '수정 청구서',
      _ => '원본',
    };

String blockerText(Object? code) => switch (code) {
      'QTY_MISMATCH' => '청구와 수령 수량이 다릅니다',
      'RECEIPT_MISSING' => '수령 기록이 연결되지 않았습니다',
      'INVOICE_MISSING' => '청구서가 없습니다',
      'DELIVERY_MISSING' => '납품 명세가 없습니다',
      'REPLACEMENT_UNCONFIRMED' => '수정 청구서의 대체 대상을 확인해야 합니다',
      'UNIT_MISMATCH' => '단위 환산 기준이 없습니다',
      'SUPPLIER_MISMATCH' => '다른 거래처 자료가 섞여 있습니다',
      _ => code?.toString() ?? '확인할 자료가 남아 있습니다',
    };

// ------------------------------------------------------------------- status

enum Tone { warn, ok, info, error, neutral }

class Status {
  const Status(this.text, this.tone);
  final String text;
  final Tone tone;
}

/// Chip for one delivery row (SCR-01 list, SCR-06 header).
Status itemStatus(Json item) {
  if (item['received_qty'] == null) return const Status('실입고 미확인', Tone.warn);
  final d = decimal(item['delta_qty']);
  final unit = item['unit'] ?? '';
  if (d == null) return const Status('차이 미확인', Tone.warn);
  if (d > 0) return Status('${item['delta_qty']}$unit 수량 확인 중', Tone.warn);
  if (d < 0) {
    return Status(
        '수령 기록이 청구보다 ${item['delta_qty'].toString().replaceFirst('-', '')}$unit 많음',
        Tone.warn);
  }
  return const Status('수량 일치', Tone.ok);
}

/// Chip for the whole period.
Status periodStatus(Json data) {
  if (data['work_status'] == 'APPROVED' || data['approved_amount'] != null) {
    return const Status('승인 완료', Tone.ok);
  }
  if (data['can_approve'] == true) return const Status('승인 가능', Tone.info);
  final summary = object(data['summary']);
  if (data['work_status'] == 'WAITING_REPLY' &&
      decimal(summary['delta_qty']) != null) {
    return itemStatus(summary);
  }
  if (summary['received_qty'] == null && objects(data['items']).isNotEmpty) {
    return const Status('실입고 미확인', Tone.warn);
  }
  return const Status('자료 확인 필요', Tone.neutral);
}

// ------------------------------------------------------------------ widgets

/// Mobile-first page: white app bar with back arrow, centered column up to
/// 560px, optional sticky bottom actions.
class Screen extends StatelessWidget {
  const Screen(
      {super.key,
      required this.title,
      required this.children,
      this.bottom = const [],
      this.leading = true,
      this.homeEnabled = true,
      this.homeDraft = false,
      this.appBarActions = const [],
      this.floatingActionButton});
  final String title;
  final List<Widget> children;
  final List<Widget> bottom;
  final bool leading;
  final bool homeEnabled;
  final bool homeDraft;
  final List<Widget> appBarActions;

  /// Bottom-right action, e.g. the start screen's camera button.
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: floatingActionButton,
        appBar: AppBar(
          title: Text(keepWords(title),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          automaticallyImplyLeading: leading,
          actions: [...appBarActions, if (leading) StartButton(enabled: homeEnabled, draft: homeDraft)],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(children: [
                Expanded(
                  child: ListView(
                    // Leave room so the floating button (96px + 16px margin) never covers the last row.
                    padding: EdgeInsets.fromLTRB(
                        20, 20, 20, floatingActionButton == null ? 28 : 128),
                    children: [if (demo) const DemoBanner(), ...children],
                  ),
                ),
                if (bottom.isNotEmpty)
                  Container(
                    decoration: const BoxDecoration(
                        color: Palette.canvas,
                        border: Border(top: BorderSide(color: Palette.line))),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: gap(bottom, 10)),
                  ),
              ]),
            ),
          ),
        ),
      );
}

List<Widget> gap(List<Widget> items, double size) => [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) SizedBox(height: size),
        items[i],
      ]
    ];

/// Shown on every screen while the in-memory example backend answers.
/// Lets the tester jump between A stages (null receipt, 0kg receipt ...).
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = demoBackend!;
    // Rebuild the scenario label whenever the example period is reloaded.
    ref.watch(settlementProvider(DemoBackend.periodId));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
          color: Palette.infoBg, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.science_outlined, size: 18, color: Palette.infoInk),
        const SizedBox(width: 8),
        Expanded(
            child: Text(keepWords('공개 A 예시 응답 · 서버 미연결'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: appFont,
                    fontSize: 13,
                    color: Palette.infoInk,
                    fontWeight: FontWeight.w600))),
        // Capped so a long scenario label never squeezes the banner text.
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: PopupMenuButton<DemoScenario>(
          tooltip: '예시 상황 바꾸기',
          onSelected: (value) {
            backend.reset(value);
            refreshPeriod(ref, DemoBackend.periodId);
            ref.invalidate(approvalProvider);
          },
          itemBuilder: (_) => [
            for (final s in DemoScenario.values)
              CheckedPopupMenuItem(
                  value: s,
                  checked: s == backend.scenario,
                  child: Text(s.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(backend.scenario.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: appFont,
                    fontSize: 13,
                    color: Palette.infoInk,
                    decoration: TextDecoration.underline)),
          ),
        )),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final Status status;
  @override
  Widget build(BuildContext context) {
    final (bg, ink) = switch (status.tone) {
      Tone.warn => (Palette.warnBg, Palette.warnInk),
      Tone.ok => (Palette.okBg, Palette.okInk),
      Tone.info => (Palette.infoBg, Palette.infoInk),
      Tone.error => (Palette.errBg, Palette.errInk),
      Tone.neutral => (Palette.canvas, Palette.muted),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(keepWords(status.text),
            style: TextStyle(
                fontFamily: appFont,
                fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
      ),
    );
  }
}

/// Grey bordered row: label left, bold value right (Figma list row).
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value,
      {super.key,
      this.onTap,
      this.caption,
      this.valueColor,
      this.stacked = false});
  final String label;

  /// Puts the value on its own line under the label, for long values such
  /// as '청구 60kg · 수령 실입고 미확인' on narrow phones.
  final bool stacked;
  final String value;
  final String? caption;
  final VoidCallback? onTap;
  final Color? valueColor;
  /// True when [value] does not fit on one line in [maxWidth].
  bool _overflows(BuildContext context, double maxWidth) {
    final painter = TextPainter(
        text: TextSpan(text: value, style: Txt.value),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Palette.canvas,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Palette.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            // The value hugs the right edge and may take up to 60% of the
            // row; the label column gets the rest. A value that would wrap
            // there moves to its own line under the label instead.
            child: LayoutBuilder(
              builder: (context, box) => stacked ||
                      _overflows(context, box.maxWidth * 0.6)
                ? Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(keepWords(label), style: Txt.label),
                            const SizedBox(height: 4),
                            Text(value,
                                style: Txt.value.copyWith(color: valueColor)),
                            if (caption != null) ...[
                              const SizedBox(height: 4),
                              Text(caption!, style: Txt.caption),
                            ],
                          ]),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 20, color: Palette.muted),
                    ],
                  ])
                : Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(keepWords(label), style: Txt.label),
                              if (caption != null) ...[
                                const SizedBox(height: 2),
                                Text(caption!, style: Txt.caption),
                              ],
                            ]),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: box.maxWidth * 0.6),
                        child: Text(value,
                            textAlign: TextAlign.right,
                            style: Txt.value.copyWith(color: valueColor)),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            size: 20, color: Palette.muted),
                      ],
                    ]),
            ),
          ),
        ),
      );
}

/// Light-blue rounded panel (청구액 카드, 질문 카드).
class TintCard extends StatelessWidget {
  const TintCard({super.key, required this.child, this.color = Palette.tint});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.caption});
  final String text;
  final String? caption;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(keepWords(text), style: Txt.section),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption!, style: Txt.label),
          ],
        ]),
      );
}

/// Loading / error wrapper for providers with a retry button.
Widget loaded<T>(AsyncValue<T> value, Widget Function(T) render,
        {VoidCallback? retry}) =>
    value.when(
      skipLoadingOnRefresh: false,
      data: render,
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Text(e.toString(), style: Txt.body, textAlign: TextAlign.center),
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('다시 불러오기')),
          ],
        ]),
      ),
      loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator())),
    );

void notify(BuildContext context, Object message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message.toString())));
}

/// Simple yes/no confirmation; returns true only on the confirm button.
Future<bool> confirmDialog(BuildContext context,
        {required String title,
        required Widget body,
        String confirm = '확인'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepWords(title)),
        content: SingleChildScrollView(child: body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(keepWords(confirm))),
        ],
      ),
    ) ??
    false;

// ---------------------------------------------------------------- originals

/// Button label for an evidence kind.
String originalLabel(Object? kind) => switch (kind) {
      'DELIVERY' => '명세서 원본 보기',
      'RECEIPT' => '수령 기록 보기',
      'INVOICE' => '청구서 원본 보기',
      'CORRECTED_INVOICE' => '수정 청구서 원본 보기',
      _ => '원본 보기',
    };

String locationText(Object? location) {
  final loc = object(location);
  final page = loc['page'];
  final row = loc['row'];
  if (page == null && row == null) {
    return loc['text'] != null ? '문서 하단 문구' : '위치 미확인';
  }
  return '${page ?? '—'}쪽${row == null ? '' : ' $row행'}';
}

/// Opens the stored original of [ref] (document_id, line_id, kind,
/// source_location) and points at the referenced row.
Future<void> showOriginal(BuildContext context, Json ref) {
  final id = ref['document_id']?.toString();
  if (id == null) {
    notify(context, '연결된 원본이 없습니다.');
    return Future.value();
  }
  final bytes = backend.original(id);
  final loc = object(ref['source_location']);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(keepWords(docTypeText(ref['kind'])),
                          style: Txt.section),
                      const SizedBox(height: 4),
                      Text('해당 줄 · ${locationText(loc)}', style: Txt.label),
                    ]),
              ),
              IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          if (loc['text'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              // A long quote scrolls on its own so the original below keeps
              // its room on short screens.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                    child: TintCard(
                        child: Text('“${loc['text']}”', style: Txt.body))),
              ),
            ),
          Flexible(
            child: FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, state) {
                if (state.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child:
                        Text('원본을 열지 못했습니다. ${state.error}', style: Txt.body),
                  );
                }
                if (!state.hasData) {
                  return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()));
                }
                if (state.data!.isEmpty && demoBackend != null) {
                  return _DemoOriginal(
                      demoBackend!.documentText(id), loc['row']);
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(state.data!, fit: BoxFit.contain),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    ),
  );
}

class _DemoOriginal extends StatelessWidget {
  const _DemoOriginal(this.doc, this.row);
  final Json? doc;
  final Object? row;
  @override
  Widget build(BuildContext context) {
    if (doc == null)
      return const Padding(
          padding: EdgeInsets.all(20), child: Text('예시 원본이 없습니다.'));
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        shrinkWrap: true,
        children: [
          Text('예시 원본 (텍스트 표시)', style: Txt.caption),
          const SizedBox(height: 8),
          Text(doc!['title'].toString(), style: Txt.title),
          const SizedBox(height: 8),
          for (final h in (doc!['header'] as List))
            Text(h.toString(), style: Txt.label),
          const SizedBox(height: 12),
          for (final r in objects(doc!['rows']))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: r['row'] == row ? Palette.warnBg : Palette.canvas,
                border: Border.all(
                    color: r['row'] == row ? Palette.warnInk : Palette.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${r['row']}행 · ${r['text']}', style: Txt.body),
            ),
          if (doc!['footer'] != null) ...[
            const SizedBox(height: 8),
            Text(doc!['footer'].toString(), style: Txt.body),
          ],
        ]);
  }
}

/// Row of buttons opening each evidence original of an item.
class EvidenceButtons extends StatelessWidget {
  const EvidenceButtons(this.refs, {super.key});
  final List<Json> refs;
  @override
  Widget build(BuildContext context) {
    final usable = refs.where((r) => r['document_id'] != null).toList();
    if (usable.isEmpty) return const Text('연결된 원본이 아직 없습니다.', style: Txt.label);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth >= 420 && usable.length > 1
          ? (box.maxWidth - 10) / 2
          : box.maxWidth;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final r in usable)
          SizedBox(
            width: width,
            child: OutlinedButton(
              onPressed: () => showOriginal(context, r),
              child: Text(keepWords(originalLabel(r['kind'])),
                  textAlign: TextAlign.center),
            ),
          ),
      ]);
    });
  }
}

/// Runs a server action with a busy flag and maps errors to a snackbar.
/// [setBusy] must check `mounted` itself before calling setState.
/// Returns the caught error so callers can react to 409 (stale screen).
Future<Object?> guarded(BuildContext context, void Function(bool) setBusy,
    Future<void> Function() action) async {
  setBusy(true);
  try {
    await action();
    return null;
  } catch (e) {
    if (context.mounted) notify(context, e);
    return e;
  } finally {
    setBusy(false);
  }
}
