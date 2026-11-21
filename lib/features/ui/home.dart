import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';

/// SCR-01 정산 홈: this week's bill, deliveries to check, payment record and
/// approval history of one period. Every amount and status is the server's.
class HomeScreen extends ConsumerWidget {
  const HomeScreen(this.periodId, {super.key});
  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlement = ref.watch(settlementProvider(periodId));
    final data = settlement.valueOrNull;
    return Screen(
      title: '정산 홈',
      children: [
        loaded(settlement, (data) => _Body(periodId, data),
            retry: () => ref.invalidate(settlementProvider(periodId))),
      ],
      bottom: [
        OutlinedButton(
          onPressed: () => context.go(uploadRoute(periodId)),
          child: const Text('자료 올리기'),
        ),
        _primaryButton(context, data),
      ],
    );
  }

  Widget _primaryButton(BuildContext context, Json? data) {
    if (data != null && data['can_approve'] == true) {
      return FilledButton(
        onPressed: () => context.go(approveRoute(periodId)),
        child: const Text('청구액 확인 · 승인'),
      );
    }
    if (data != null && data['work_status'] == 'APPROVED') {
      final approvalId = data['approval_id'];
      return FilledButton(
        onPressed: () => context.go(approvalId == null
            ? approvalsRoute(periodId)
            : approvalRoute(approvalId)),
        child: const Text('승인본 보기'),
      );
    }
    final items = data == null ? <Json>[] : objects(data['items']);
    final target = items.isEmpty
        ? null
        : items.firstWhere((i) => itemStatus(i).tone == Tone.warn,
            orElse: () => items.first);
    return FilledButton(
      onPressed: target == null
          ? null
          : () =>
              context.go(transactionRoute(periodId, target['transaction_id'])),
      child: const Text('확인할 거래 보기'),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.periodId, this.data);
  final String periodId;
  final Json data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = objects(data['items']);
    final blockers =
        data['blockers'] is List ? data['blockers'] as List : const [];
    final due = paymentDue(data);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(supplierName(ref, data), style: Txt.title),
            const SizedBox(height: 6),
            Text('주간 정산 · ${periodText(data)}', style: Txt.label),
          ]),
        ),
        TextButton.icon(
          onPressed: () => refreshPeriod(ref, periodId),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('새로고침'),
        ),
      ]),
      const SizedBox(height: 20),
      _BillCard(data),
      const SizedBox(height: 10),
      InfoRow('승인액', won(data['approved_amount']),
          caption:
              data['approved_amount'] == null ? '점주가 승인하기 전에는 비어 있습니다' : null),
      SectionTitle('확인할 납품', caption: '납품 건별 청구와 수령 수량입니다. 주간 합계와 따로 봅니다.'),
      StatusChip(periodStatus(data)),
      const SizedBox(height: 12),
      if (items.isEmpty)
        const Text('아직 납품 자료가 없습니다. 자료 올리기로 납품 명세·수령 기록·청구서를 올리세요.',
            style: Txt.body)
      else
        ...gap([
          for (final item in items)
            InfoRow(
              '${dayText(item['delivery_date'])} ${item['delivery_no'] ?? ''}',
              '청구 ${qtyText(item, 'billed_qty')} · 수령 ${receivedText(item)}',
              caption: _itemCaption(item),
              stacked: true,
              onTap: () => context
                  .go(transactionRoute(periodId, item['transaction_id'])),
            ),
        ], 10),
      if (blockers.isNotEmpty) ...[
        const SizedBox(height: 16),
        TintCard(
          color: Palette.warnBg,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('승인 전에 확인할 것',
                style:
                    Txt.value.copyWith(fontSize: 14, color: Palette.warnInk)),
            const SizedBox(height: 6),
            for (final code in blockers)
              Text('· ${blockerText(code)}',
                  style: Txt.body.copyWith(color: Palette.warnInk)),
          ]),
        ),
      ],
      const SectionTitle('합의한 지급일과 송금 기록'),
      ...gap([
        InfoRow('지급일', due == null ? '미확인' : dayText(due),
            caption: due == null ? null : '청구서에 적힌 합의 지급일'),
        InfoRow('송금 확인', paymentText(data['payment_status'])),
      ], 10),
      const SizedBox(height: 8),
      const Text('청구 승인과 송금 확인은 따로 기록합니다.', style: Txt.caption),
      const SectionTitle('승인 내역'),
      _ApprovalsRow(periodId),
    ]);
  }

  String _itemCaption(Json item) {
    final lines = [
      [if (item['item'] != null) item['item'], itemStatus(item).text]
          .join(' · '),
      if (item['check_amount'] != null && decimal(item['delta_qty']) != 0)
        '확인할 차이 ${deltaText(item)} · ${won(item['check_amount'])}',
      if (item['declared_qty'] != null &&
          decimal(item['declared_qty']) != decimal(item['billed_qty']))
        '명세 ${qtyText(item, 'declared_qty')}',
    ];
    return lines.join('\n');
  }
}

/// 이번 주 청구액 card. Weekly totals only; per-delivery rows are listed below.
class _BillCard extends StatelessWidget {
  const _BillCard(this.data);
  final Json data;

  @override
  Widget build(BuildContext context) {
    final summary = object(data['summary']);
    final history = objects(data['billing_history']);
    final corrected = history
        .any((h) => h['status'] == 'CURRENT' && h['replaces_doc_no'] != null);
    final basis = history.isEmpty
        ? '청구서를 아직 받지 않았습니다'
        : corrected
            ? '수정 청구서 기준'
            : '받은 청구서 기준';
    return TintCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('이번 주 청구액', style: Txt.section),
              const SizedBox(height: 4),
              Text(basis, style: Txt.label),
            ]),
          ),
          Text(won(summary['billed_amount']), style: Txt.amount),
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1, color: Palette.line),
        const SizedBox(height: 10),
        Text(
            '주간 합계 · 청구 ${qtyText(summary, 'billed_qty')} · 실수령 ${receivedText(summary)}',
            style: Txt.label),
      ]),
    );
  }
}

/// Link to the server's approval list so a fresh browser can reach it.
class _ApprovalsRow extends ConsumerWidget {
  const _ApprovalsRow(this.periodId);
  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(approvalsProvider(periodId)).when(
          data: (rows) => rows.isEmpty ? '없음' : '${rows.length}건',
          error: (_, __) => '불러오지 못함',
          loading: () => '불러오는 중',
        );
    return InfoRow('승인 내역', count,
        caption: '승인할 때 저장한 금액과 원본을 다시 봅니다.',
        onTap: () => context.go(approvalsRoute(periodId)));
  }
}
