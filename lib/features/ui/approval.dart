import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';

/// "2026-11-17 14:00" in local time, or "—" when the server sent nothing.
String _timeText(Object? iso) {
  final t = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (t == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

Json? _historyEntry(Json data, String status) {
  for (final entry in objects(data['billing_history'])) {
    if (entry['status'] == status) return entry;
  }
  return null;
}

String _scopeText(Object? scope) => switch (scope) {
      'RECEIPTS_INCLUDED' => '수령 기록까지 확인',
      'DOCUMENTS_ONLY' => '문서만 확인 (실입고 미확인)',
      _ => '미확인',
    };

String _historyStatusText(Object? status) => switch (status) {
      'CURRENT' => '반영된 청구서',
      'REPLACED' => '대체된 이력',
      'CANDIDATE' => '대체 확인 전',
      _ => '청구서',
    };

/// Supplier and period line under the app bar (Figma 17pt heading).
class _Heading extends ConsumerWidget {
  const _Heading(this.data);
  final Json data;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text('${supplierName(ref, data)} · ${periodText(data)}', style: Txt.section),
      );
}

/// Opens the original where the supplier wrote the agreement (R04).
class _AgreementButton extends StatelessWidget {
  const _AgreementButton(this.entry);
  final Json entry;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: () => showOriginal(context, object(entry['agreement_ref'])),
        child: Text(
            keepWords(originalLabel(object(entry['agreement_ref'])['kind'] ?? 'CORRECTED_INVOICE'))),
      );
}

class _Quote extends StatelessWidget {
  const _Quote(this.text);
  final Object text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: Palette.surface,
          border: Border(left: BorderSide(color: Palette.primary, width: 3)),
        ),
        child: Text('“$text”', style: Txt.body),
      );
}

// --------------------------------------------------------------- SCR-07

/// SCR-07 정산표 승인: shows the server's approvable amount with the billing
/// history behind it and records the owner's approval.
class ApproveScreen extends ConsumerStatefulWidget {
  const ApproveScreen(this.periodId, {super.key});
  final String periodId;
  @override
  ConsumerState<ApproveScreen> createState() => _ApproveScreenState();
}

class _ApproveScreenState extends ConsumerState<ApproveScreen> {
  bool _busy = false;

  /// Set after a 409 until the owner tries again on the refreshed data.
  bool _stale = false;

  /// Request key of the approval attempt for [_keyRevision]; a retry of the
  /// same attempt resends it so the server answers with the same approval.
  String? _key;
  Object? _keyRevision;

  String get _periodId => widget.periodId;

  Future<void> _approve(Json data) async {
    final revision = data['input_revision'];
    final confirmed = await confirmDialog(
      context,
      title: keepWords('정산표를 승인할까요?'),
      confirm: '승인',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(won(data['approvable_amount']), style: Txt.amount),
          const SizedBox(height: 8),
          Text('자료 버전 ${revision ?? '—'} 기준으로 승인합니다.', style: Txt.body),
          const SizedBox(height: 4),
          const Text('송금은 별도로 확인합니다.', style: Txt.label),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    if (_keyRevision != revision) {
      _keyRevision = revision;
      _key = null;
    }
    final key = _key ??= requestKey();
    setState(() => _stale = false);

    Json saved = {};
    final error = await guarded(context, (b) {
      if (mounted) setState(() => _busy = b);
    }, () async {
      saved = await backend.post('${periodPath(_periodId)}/approvals',
          {'expected_revision': revision, 'request_key': key});
    });
    if (!mounted) return;

    if (error == null) {
      _key = null;
      refreshPeriod(ref, _periodId);
      final id = saved['approval_id'];
      context.go(id == null ? approvalsRoute(_periodId) : approvalRoute(id));
      return;
    }
    if (error is ApiError && (error.status == 409 || error.status == 422)) {
      _key = null;
      refreshPeriod(ref, _periodId);
      if (error.stale) setState(() => _stale = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settlementProvider(_periodId));
    final data = value.valueOrNull;
    return Screen(
      title: '정산표 승인',
      homeEnabled: !_busy,
      children: [
        if (_stale)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: TintCard(
              color: Palette.warnBg,
              child: Text('자료가 바뀌었습니다. 최신 근거를 확인한 뒤 다시 승인해 주세요.',
                  style: TextStyle(
                      fontFamily: appFont,
                      fontSize: 14,
                      color: Palette.warnInk,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        loaded(value, _body, retry: () => ref.invalidate(settlementProvider(_periodId))),
      ],
      bottom: data == null ? const [] : _actions(data, refreshing: value.isLoading),
    );
  }

  bool _approved(Json data) => data['work_status'] == 'APPROVED' || data['approved_amount'] != null;

  /// While the settlement reloads the old revision is still in [data], so
  /// the approve button stays disabled until the newest data is on screen.
  List<Widget> _actions(Json data, {required bool refreshing}) {
    if (_approved(data)) {
      final id = data['approval_id'];
      return [
        FilledButton(
          onPressed: () => context.go(id == null ? approvalsRoute(_periodId) : approvalRoute(id)),
          child: const Text('승인본 보기'),
        ),
        OutlinedButton(
            onPressed: () => context.go(periodRoute(_periodId)), child: const Text('정산 홈')),
      ];
    }
    if (data['can_approve'] != true) {
      return const [FilledButton(onPressed: null, child: Text('승인할 수 없음'))];
    }
    return [
      FilledButton(
        onPressed: _busy || refreshing ? null : () => _approve(data),
        child: Text(keepWords(_busy ? '승인 저장 중' : '${won(data['approvable_amount'])} 확인 · 승인'),
            textAlign: TextAlign.center),
      ),
    ];
  }

  Widget _body(Json data) {
    final summary = object(data['summary']);
    final current = _historyEntry(data, 'CURRENT');
    final replaced = _historyEntry(data, 'REPLACED');
    final corrected = current?['replaces_doc_no'] != null;
    final approved = _approved(data);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Heading(data),
      StatusChip(periodStatus(data)),
      const SizedBox(height: 14),
      TintCard(
        child: LayoutBuilder(
          builder: (context, box) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(keepWords(corrected ? '합의 뒤 받은 수정 청구서' : '받은 청구서'),
                    style: Txt.body.copyWith(fontWeight: FontWeight.w700)),
                if (summary['unit_price'] != null) ...[
                  const SizedBox(height: 6),
                  Text('${qtyText(summary, 'billed_qty')} × ${won(summary['unit_price'])}', style: Txt.label),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            // Large amounts shrink instead of squeezing the label column.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(won(summary['billed_amount']), style: Txt.amount)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ...gap([
        if (replaced != null)
          InfoRow('처음 받은 청구액', won(replaced['billed_amount']),
              stacked: true,
              caption: '${replaced['doc_no'] ?? '—'} · 이력'),
        if (corrected)
          InfoRow('수정 청구액', won(current!['billed_amount']),
              stacked: true,
              caption: '${current['doc_no'] ?? '—'}\n대체: ${current['replaces_doc_no']}'),
        if (current?['agreement_text'] != null) _Quote(current!['agreement_text']),
        if (current?['agreement_ref'] != null) _AgreementButton(current!),
        InfoRow('청구 / 실수령', '${qtyText(summary, 'billed_qty')} / ${receivedText(summary)}',
            stacked: true),
      ], 10),
      const SectionTitle('송금 정보'),
      ...gap([
        InfoRow('송금 확인', paymentText(data['payment_status']),
            caption: '송금한 내역은 별도로 확인해 주세요.'),
        InfoRow('지급일', paymentDue(data) ?? '미확인'),
      ], 10),
      const SectionTitle('승인'),
      ...gap([
        InfoRow('승인 대상액', won(data['approvable_amount']),
            caption: '자료 버전 ${data['input_revision'] ?? '—'}'),
        InfoRow('승인액', won(data['approved_amount']),
            valueColor: approved ? Palette.okInk : null),
      ], 10),
      if (!approved && data['can_approve'] != true) ...[
        const SizedBox(height: 16),
        _Blockers(data, periodId: _periodId),
      ],
      if (approved) ...[
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => context.go(approvalsRoute(_periodId)), child: const Text('승인 내역 보기')),
      ],
    ]);
  }
}

class _Blockers extends StatelessWidget {
  const _Blockers(this.data, {required this.periodId});
  final Json data;
  final String periodId;
  @override
  Widget build(BuildContext context) {
    final blockers = data['blockers'] is List ? data['blockers'] as List : const [];
    const ink = TextStyle(fontFamily: appFont, fontSize: 14, color: Palette.warnInk, height: 1.45);
    return TintCard(
      color: Palette.warnBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(keepWords('아직 승인할 수 없습니다'), style: ink.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (blockers.isEmpty) Text('· ${blockerText(null)}', style: ink),
        for (final code in blockers) Text('· ${blockerText(code)}', style: ink),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => context.go(periodRoute(periodId)),
            child: Text(keepWords('정산 홈에서 확인하기'))),
      ]),
    );
  }
}

// ------------------------------------------------------------ 승인 내역

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen(this.periodId, {super.key});
  final String periodId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Screen(
        title: '승인 내역',
        children: [
          loaded(
            ref.watch(approvalsProvider(periodId)),
            (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('저장된 승인본이 없습니다.', style: Txt.body, textAlign: TextAlign.center),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: gap([
                      for (final row in rows)
                        InfoRow(
                          won(row['approved_amount']),
                          '버전 ${row['version_no'] ?? '—'}',
                          caption: 'ID ${row['approval_id'] ?? '—'} · ${_timeText(row['approved_at'])}'
                              '${row['is_current'] == false ? ' · 이전 승인본' : ''}',
                          onTap: row['approval_id'] == null
                              ? null
                              : () => context.go(approvalRoute(row['approval_id'])),
                        ),
                    ], 10),
                  ),
            retry: () => ref.invalidate(approvalsProvider(periodId)),
          ),
        ],
        bottom: [
          OutlinedButton(
              onPressed: () => context.go(periodRoute(periodId)), child: const Text('정산 홈')),
        ],
      );
}

// --------------------------------------------------------- 승인본 상세

/// One approval as stored at approval time. Needs nothing but the URL, so a
/// fresh browser opening /approval/S shows the same amount and originals.
class ApprovalDetailScreen extends ConsumerWidget {
  const ApprovalDetailScreen(this.approvalId, {super.key});
  final String approvalId;

  static const _topLevel = [
    'approval_id',
    'approved_amount',
    'version_no',
    'approved_at',
    'approved_by',
    'payment_status',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(approvalProvider(approvalId));
    final data = value.valueOrNull;
    final periodId = data == null
        ? null
        : (data['period_id'] ?? object(data['snapshot'])['period_id'])?.toString();
    return Screen(
      title: '승인본 상세',
      children: [
        loaded(value, (data) => _body(context, data),
            retry: () => ref.invalidate(approvalProvider(approvalId))),
      ],
      bottom: [
        OutlinedButton(
          onPressed: () => context.go(periodId == null ? '/' : periodRoute(periodId)),
          child: const Text('정산 홈으로'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Json data) {
    final info = {
      ...data,
      ...object(data['snapshot']),
      for (final key in _topLevel)
        if (data[key] != null) key: data[key],
    };
    final summary = object(info['summary']);
    final history = objects(info['billing_history']);
    final items = objects(info['items']);
    final due = paymentDue(info);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (info['period_start'] != null) _Heading(info),
      const StatusChip(Status('승인 완료', Tone.ok)),
      const SizedBox(height: 14),
      TintCard(
        child: LayoutBuilder(
          builder: (context, box) => Row(children: [
            Expanded(child: Text('승인액', style: Txt.body.copyWith(fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(won(info['approved_amount']), style: Txt.amount)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ...gap([
        InfoRow('승인 ID', (info['approval_id'] ?? approvalId).toString(), stacked: true),
        InfoRow('버전', '${info['version_no'] ?? '—'}'),
        InfoRow('자료 버전', '${info['input_revision'] ?? '—'}'),
        InfoRow('확인 범위', _scopeText(info['confirmation_scope']), stacked: true),
        InfoRow('승인한 사람', (info['approved_by'] ?? '—').toString()),
        InfoRow('승인 시각', _timeText(info['approved_at'])),
      ], 10),
      const SectionTitle('송금 정보'),
      ...gap([
        InfoRow('송금 확인', paymentText(info['payment_status']),
            caption: '승인과 송금 확인은 별개입니다.'),
        if (due != null) InfoRow('지급일', due),
      ], 10),
      SectionTitle(keepWords('승인 당시 청구와 수령')),
      ...gap([
        InfoRow('청구 / 실수령', '${qtyText(summary, 'billed_qty')} / ${receivedText(summary)}',
            stacked: true),
        InfoRow('청구액', won(summary['billed_amount'])),
        for (final entry in history) ...[
          InfoRow(
            '${docTypeText(entry['replaces_doc_no'] == null ? 'INVOICE' : 'CORRECTED_INVOICE')} '
            '${entry['doc_no'] ?? ''}',
            won(entry['billed_amount']),
            stacked: true,
            caption: [
              _historyStatusText(entry['status']),
              if (entry['replaces_doc_no'] != null) '대체: ${entry['replaces_doc_no']}',
            ].join(' · '),
          ),
          if (entry['agreement_text'] != null) _Quote(entry['agreement_text']),
          if (entry['agreement_ref'] != null) _AgreementButton(entry),
        ],
      ], 10),
      if (items.isNotEmpty) ...[
        SectionTitle(keepWords('승인 당시 원본'), caption: '승인할 때 저장된 원본을 그대로 엽니다.'),
        ...gap([for (final item in items) _SnapshotItem(item)], 12),
      ],
    ]);
  }
}

class _SnapshotItem extends StatelessWidget {
  const _SnapshotItem(this.item);
  final Json item;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Palette.surface,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${dayText(item['delivery_date'])} · ${item['delivery_no'] ?? '번호 미확인'}',
              style: Txt.value),
          if (item['item'] != null) ...[
            const SizedBox(height: 2),
            Text(item['item'].toString(), style: Txt.label),
          ],
          const SizedBox(height: 8),
          Text('청구 ${qtyText(item, 'billed_qty')} · 실수령 ${receivedText(item)}', style: Txt.body),
          const SizedBox(height: 12),
          EvidenceButtons(objects(item['evidence_refs'])),
        ]),
      );
}
