import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_calendar_grid.dart';
import 'package:holybeans/ui/cafes/cafe_share_text.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

class _DriveDates extends ChangeNotifier implements DriveSyncModel {
  _DriveDates(this.lastBackupAt);
  @override
  final DateTime lastBackupAt;
  @override
  bool get enabled => true;
  @override
  bool get busy => false;
  @override
  bool get restoring => false;
  @override
  bool get copiesLoaded => true;
  @override
  String get deviceId => 'phone';
  @override
  DriveSyncStatus get status => DriveSyncStatus.current;
  @override
  List<DriveBackupCopy> get copies => [
    DriveBackupCopy(
      DriveSnapshot(
        id: 'copy',
        deviceId: deviceId,
        contentHash: 'a' * 64,
        createdAt: lastBackupAt.toUtc(),
      ),
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, Locale language) => MaterialApp(
  locale: language,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: child,
);

void main() {
  setUpAll(initializeDateFormatting);
  final time = DateTime(2026, 11, 23, 15, 4, 5);
  for (final (region, expectedDate) in [
    (const Locale('es', 'ES'), '23/11/2026'),
    (const Locale('en', 'GB'), '23/11/2026'),
    (const Locale('en', 'US'), '11/23/2026'),
    (const Locale('de', 'DE'), '23.11.2026'),
    (const Locale('ja', 'JP'), '2026/11/23'),
  ]) {
    final language = Locale(region.languageCode == 'en' ? 'es' : 'en');
    for (final force24 in [false, true]) {
      testWidgets('Drive dates follow $region, app $language, 24h $force24', (
        tester,
      ) async {
        final dispatcher = tester.platformDispatcher;
        dispatcher.localeTestValue = region;
        dispatcher.alwaysUse24HourFormatTestValue = force24;
        addTearDown(dispatcher.clearLocaleTestValue);
        addTearDown(dispatcher.clearAlwaysUse24HourTestValue);
        final model = _DriveDates(time);
        addTearDown(model.dispose);
        await tester.pumpWidget(_app(DriveSyncPage(model: model), language));
        await tester.pumpAndSettle();
        final s = lookupAppLocalizations(language);
        final clock = force24
            ? '15:04'
            : DateFormat.jm(region.toString()).format(time);
        final seconds = force24
            ? '15:04:05'
            : DateFormat.jms(region.toString()).format(time);
        expect(
          find.text(s.driveBackupLast('$expectedDate $clock')),
          findsOneWidget,
        );
        expect(find.text('$expectedDate $seconds'), findsOneWidget);
        expect(find.text(s.driveSyncTitle), findsOneWidget);
      });
    }

    testWidgets(
      'shared cafe date and statistics follow $region, app $language',
      (tester) async {
        tester.platformDispatcher.localeTestValue = region;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        late List<CafeShareRow> rows;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                rows = cafeShareRows(
                  context,
                  const Cafe(
                    id: 'c',
                    name: 'Cafe',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  CafeDrink(
                    id: 'd',
                    cafeId: 'c',
                    drinkType: 'Coffee',
                    currency: 'EUR',
                    drankAtMs: time.millisecondsSinceEpoch,
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  null,
                );
                return const SizedBox.shrink();
              },
            ),
            language,
          ),
        );
        expect(rows.singleWhere((row) => row.id == 'date').value, expectedDate);
        final s = lookupAppLocalizations(language);
        expect(
          statsPeriodLabel(s, time, StatsPeriod.week, long: true),
          s.statsWeekOf(DateFormat.MMMd(region.toString()).format(time)),
        );
        expect(
          statsPeriodLabel(s, time, StatsPeriod.month, long: true),
          DateFormat.yMMMM(region.toString()).format(time),
        );
      },
    );
  }

  for (final (region, sundayFirst) in [
    (const Locale('es', 'ES'), false),
    (const Locale('en', 'GB'), false),
    (const Locale('en', 'US'), true),
  ]) {
    testWidgets('calendar week starts by region $region despite app language', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = region;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final day = DateTime(2026, 11);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: FreshnessCalendarGrid(
              month: day,
              today: day,
              selected: day,
              days: const {},
              onSelected: (_) {},
            ),
          ),
          Locale(sundayFirst ? 'es' : 'en'),
        ),
      );
      final first = find.byKey(const ValueKey('calendar-day-2026-11-01'));
      final second = find.byKey(const ValueKey('calendar-day-2026-11-02'));
      expect(
        tester.getTopLeft(first).dx < tester.getTopLeft(second).dx,
        sundayFirst,
      );
      expect(
        find.byTooltip(
          RegExp(
            RegExp.escape(DateFormat.yMMMMEEEEd(region.toString()).format(day)),
          ),
        ),
        findsOneWidget,
      );
    });
  }
}
