import 'package:holybeans/domain/freshness.dart';

int compareFreshness(
  FreshnessToday? first,
  FreshnessToday? second, {
  required bool ascending,
}) {
  // Unknown freshness stays last in either direction.
  if (first == null) return second == null ? 0 : 1;
  if (second == null) return -1;
  final byPhase = second.phase.index.compareTo(first.phase.index);
  if (byPhase != 0) return ascending ? -byPhase : byPhase;

  // Within a phase, use the coffee closest to its end first. Beyond the
  // last window, the coffee furthest past that window is most urgent.
  int remaining(FreshnessToday value) =>
      value.window.daysLeftInPhase(value.day) ??
      value.window.agingUntil - value.day;
  final byRemaining = remaining(first).compareTo(remaining(second));
  return ascending ? -byRemaining : byRemaining;
}
