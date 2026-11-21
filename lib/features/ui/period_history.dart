import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'shared.dart';

class PeriodHistory extends StatefulWidget {
  const PeriodHistory({super.key, required this.rows});

  final List<Json> rows;

  @override
  State<PeriodHistory> createState() => _PeriodHistoryState();
}

class _PeriodHistoryState extends State<PeriodHistory> {
  int _year = 0;
  DateTimeRange? _range;

  DateTimeRange? _dates(Json row) {
    final start = DateTime.tryParse(row['period_start']?.toString() ?? '');
    final end = DateTime.tryParse(row['period_end']?.toString() ?? '');
    if (start == null || end == null || end.isBefore(start)) return null;
    return DateTimeRange(
      start: DateUtils.dateOnly(start),
      end: DateUtils.dateOnly(end),
    );
  }

  Future<void> _pickRange(List<int> years) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(years.last),
      lastDate: DateTime(years.first, 12, 31),
      helpText: '달력에서 기간 선택',
      saveText: '조회',
      confirmText: '조회',
      cancelText: '취소',
      fieldStartLabelText: '시작 날짜',
      fieldEndLabelText: '종료 날짜',
      errorInvalidRangeText: '종료 날짜는 시작 날짜보다 빠를 수 없습니다.',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _year = 0;
      _range = picked;
    });
  }

  String _dateLabel(DateTime date) => '${date.year}.${date.month}.${date.day}';

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return const Text('조회할 정산 기간이 없습니다.', style: Txt.body);
    }

    final entries = [
      for (final row in widget.rows) (row: row, dates: _dates(row)),
    ];
    final years = {
      for (final entry in entries)
        if (entry.dates case final dates?) ...[
          dates.start.year,
          dates.end.year
        ],
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final range = _range;
    final selectedDates = range ??
        (_year == 0
            ? null
            : DateTimeRange(
                start: DateTime(_year),
                end: DateTime(_year, 12, 31),
              ));
    final visible = entries.where((entry) {
      final dates = entry.dates;
      return selectedDates == null ||
          (dates != null &&
              !dates.end.isBefore(selectedDates.start) &&
              !dates.start.isAfter(selectedDates.end));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: gap([
        if (years.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: _year,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('전체 연도')),
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text('$year년')),
                ],
                onChanged: (year) {
                  if (year == null) return;
                  setState(() {
                    _year = year;
                    _range = null;
                  });
                },
              ),
              OutlinedButton.icon(
                onPressed: () => _pickRange(years),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('달력에서 기간 선택'),
              ),
            ],
          ),
        if (range != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(
                '${_dateLabel(range.start)} ~ ${_dateLabel(range.end)}',
              ),
              deleteButtonTooltipMessage: '기간 선택 해제',
              onDeleted: () => setState(() => _range = null),
            ),
          ),
        if (visible.isEmpty)
          const Text('선택한 기간에 저장된 정산이 없습니다.', style: Txt.body),
        for (final entry in visible)
          InfoRow(
            periodText(entry.row),
            '열기',
            caption: entry.row['label']?.toString(),
            onTap: () => context.go(
              periodRoute(entry.row['period_id'].toString()),
            ),
          ),
      ], 10),
    );
  }
}
