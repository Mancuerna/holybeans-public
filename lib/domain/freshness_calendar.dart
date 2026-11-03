import 'package:holybeans/domain/freshness.dart';

class CalendarLot {
  const CalendarLot({
    required this.id,
    required this.coffeeId,
    required this.coffeeName,
    required this.roaster,
    required this.grams,
    this.roastDate,
    this.openedDate,
    this.roastLevel,
    this.restDays,
    this.frozenPauseDays = 0,
    this.frozen = false,
  });

  final String id;
  final String coffeeId;
  final String coffeeName;
  final String roaster;
  final double? grams;
  final DateTime? roastDate;
  final DateTime? openedDate;
  final String? roastLevel;
  final int? restDays;
  final int frozenPauseDays;
  final bool frozen;

  FreshnessPhase? phaseOn(DateTime date, BrewStyle style) {
    final roast = roastDate;
    if (frozen || roast == null) return null;
    final age = effectiveRoastAge(
      roast,
      date,
      frozenPauseDays: frozenPauseDays,
      openedDate: openedDate,
    );
    if (age == null) return null;
    return freshnessWindow(
      roastLevel: roastLevel,
      style: style,
      restDays: restDays,
    ).phaseAt(age);
  }
}

class CalendarDay {
  CalendarDay(Iterable<CalendarLot> lots, DateTime date, BrewStyle style) {
    for (final lot in lots) {
      if (lot.grams != null && lot.grams! <= 0) continue;
      if (lot.frozen) {
        frozen.add(lot);
      } else {
        final phase = lot.phaseOn(date, style);
        if (phase == null) {
          unknown.add(lot);
        } else {
          (phases[phase] ??= []).add(lot);
        }
      }
    }
  }

  final phases = <FreshnessPhase, List<CalendarLot>>{};
  final unknown = <CalendarLot>[];
  final frozen = <CalendarLot>[];
}
