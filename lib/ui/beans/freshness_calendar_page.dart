import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/freshness_calendar.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_calendar_grid.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class FreshnessCalendarPage extends StatefulWidget {
  const FreshnessCalendarPage({
    super.key,
    required this.lots,
    required this.onCoffee,
    this.now,
  });

  final List<CalendarLot> lots;
  final ValueChanged<String> onCoffee;
  final DateTime? now;

  @override
  State<FreshnessCalendarPage> createState() => _FreshnessCalendarPageState();
}

class _FreshnessCalendarPageState extends State<FreshnessCalendarPage>
    with WidgetsBindingObserver {
  late DateTime today;
  late DateTime selected;
  late DateTime month;
  BrewStyle style = BrewStyle.filter;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    today = DateTime(now.year, now.month, now.day);
    selected = today;
    month = DateTime(today.year, today.month);
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    if (widget.now != null) return;
    final now = DateTime.now();
    _midnight = Timer(nextLocalDayStart(now).difference(now), _refreshDay);
  }

  void _refreshDay() {
    final now = widget.now ?? DateTime.now();
    setState(() {
      today = DateTime(now.year, now.month, now.day);
      if (selected.isBefore(today)) {
        selected = today;
        month = DateTime(today.year, today.month);
      }
    });
    _scheduleMidnight();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _changeMonth(int step) => setState(() {
    month = DateTime(month.year, month.month + step);
    selected = month.isBefore(today) ? today : month;
  });

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final days = <DateTime, CalendarDay>{};
    for (
      var day = 1;
      day <= DateTime(month.year, month.month + 1, 0).day;
      day++
    ) {
      final date = DateTime(month.year, month.month, day);
      if (!date.isBefore(today)) {
        days[date] = CalendarDay(widget.lots, date, style);
      }
    }
    final selection =
        days[selected] ?? CalendarDay(widget.lots, selected, style);
    final currentMonth = DateTime(today.year, today.month);
    return Scaffold(
      appBar: AppBar(title: Text(s.freshnessCalendar)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final value in BrewStyle.values)
                ChoiceChip(
                  key: ValueKey('calendar-style-${value.name}'),
                  label: Text(brewStyleLabel(s, value)),
                  selected: style == value,
                  onSelected: (_) => setState(() => style = value),
                ),
              TextButton(
                key: const ValueKey('calendar-today'),
                onPressed: () => setState(() {
                  month = currentMonth;
                  selected = today;
                }),
                child: Text(s.freshnessCalendarToday),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                key: const ValueKey('calendar-previous'),
                tooltip: material.previousMonthTooltip,
                onPressed: month.isAfter(currentMonth)
                    ? () => _changeMonth(-1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(regionalLocale.toString()).format(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('calendar-next'),
                tooltip: material.nextMonthTooltip,
                onPressed: month.isBefore(DateTime(today.year + 1, today.month))
                    ? () => _changeMonth(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          FreshnessCalendarGrid(
            month: month,
            today: today,
            selected: selected,
            days: days,
            onSelected: (date) => setState(() => selected = date),
          ),
          const SizedBox(height: 12),
          Text(
            s.freshnessCalendarForecast,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Text(
            DateFormat.yMMMMEEEEd(regionalLocale.toString()).format(selected),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (widget.lots.isEmpty) Text(s.freshnessCalendarEmpty),
          for (final phase in FreshnessPhase.values)
            if (selection.phases[phase] case final lots?)
              _LotSection(
                title: freshnessPhaseLabel(s, phase),
                color: freshnessPhaseColor(context, phase),
                lots: lots,
                onCoffee: widget.onCoffee,
              ),
          if (selection.unknown.isNotEmpty)
            _LotSection(
              title: s.freshnessCalendarUnknown,
              lots: selection.unknown,
              onCoffee: widget.onCoffee,
            ),
          if (selection.frozen.isNotEmpty)
            _LotSection(
              title: s.freshnessCalendarFrozen,
              lots: selection.frozen,
              onCoffee: widget.onCoffee,
            ),
        ],
      ),
    );
  }
}

class _LotSection extends StatelessWidget {
  const _LotSection({
    required this.title,
    required this.lots,
    required this.onCoffee,
    this.color,
  });

  final String title;
  final List<CalendarLot> lots;
  final ValueChanged<String> onCoffee;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('calendar-section-$title'),
        initiallyExpanded: true,
        title: Text(title, style: TextStyle(color: color)),
        subtitle: Text(s.freshnessCalendarLotCount(lots.length)),
        children: [
          for (final lot in lots)
            ListTile(
              key: ValueKey('calendar-lot-${lot.id}'),
              title: Text(lot.coffeeName),
              subtitle: Text(
                [
                  if (lot.roaster.isNotEmpty) lot.roaster,
                  lot.roastDate == null
                      ? s.freshnessCalendarNoDate
                      : s.freshnessCalendarRoasted(
                          formatRegionalDate(lot.roastDate!, regionalLocale),
                        ),
                  lot.grams == null
                      ? s.unknownStock
                      : formatGrams(lot.grams!, regionalLocale.toString()),
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onCoffee(lot.coffeeId),
            ),
        ],
      ),
    );
  }
}
