import 'package:flutter/material.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/freshness_calendar.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class FreshnessCalendarGrid extends StatelessWidget {
  const FreshnessCalendarGrid({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.days,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final Map<DateTime, CalendarDay> days;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final symbols = DateFormat.yMd(regionalLocale.toString()).dateSymbols;
    final first = (symbols.FIRSTDAYOFWEEK + 1) % 7;
    final offset = (month.weekday % 7 - first + 7) % 7;
    final length = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + length) / 7).ceil() * 7;
    final scale = MediaQuery.textScalerOf(context);
    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < 7; index++)
              Expanded(
                child: Center(
                  child: Text(symbols.NARROWWEEKDAYS[(index + first) % 7]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: scale.scale(16) + scale.scale(12) + 40,
            mainAxisSpacing: 4,
            crossAxisSpacing: 3,
          ),
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > length) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, number);
            final day = days[date];
            final enabled = !date.isBefore(today);
            final counts = {
              for (final phase in FreshnessPhase.values)
                if (day?.phases[phase] case final lots?) phase: lots.length,
            };
            final total = counts.values.fold(0, (sum, count) => sum + count);
            final label = [
              DateFormat.yMMMMEEEEd(regionalLocale.toString()).format(date),
              if (enabled) s.freshnessCalendarLotCount(total),
              for (final count in counts.entries)
                '${freshnessPhaseLabel(s, count.key)}: ${count.value}',
            ].join('. ');
            return Semantics(
              label: label,
              selected: date == selected,
              enabled: enabled,
              button: true,
              onTap: enabled ? () => onSelected(date) : null,
              child: ExcludeSemantics(
                child: Tooltip(
                  message: label,
                  child: Material(
                    color: date == selected
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      key: ValueKey(
                        'calendar-day-${formatIsoCalendarDate(date)}',
                      ),
                      borderRadius: BorderRadius.circular(10),
                      onTap: enabled ? () => onSelected(date) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                NumberFormat.decimalPattern(
                                  regionalLocale.toString(),
                                ).format(number),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: date == today
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: enabled
                                      ? null
                                      : Theme.of(context).disabledColor,
                                ),
                              ),
                            ),
                            if (enabled) ...[
                              Row(
                                children: [
                                  for (final count in counts.entries)
                                    Expanded(
                                      flex: count.value,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 0.5,
                                        ),
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: freshnessPhaseColor(
                                            context,
                                            count.key,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  NumberFormat.decimalPattern(
                                    regionalLocale.toString(),
                                  ).format(total),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
