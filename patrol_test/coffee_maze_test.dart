import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/domain/coffee_maze.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_page.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_painter.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/settings/settings_page.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'coffee break pauses when Android backgrounds the app',
    tags: ['android', 'coffee-maze'],
    ($) async {
      expect(
        await const DriveNativeClient().channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await $.pumpWidgetAndSettle(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsPage(
              locale: const Locale('es'),
              onLocaleChanged: (_) {},
              onExportBackup: () {},
              onExportCsv: () {},
              onImportBackup: () {},
              parameterSettings: BrewParameterSettings(db),
              templateSettings: ShareTemplateSettings(db),
            ),
          ),
        );
        final version = find.byKey(const ValueKey('app-version'));
        await $.scrollUntilVisible(finder: $(version));
        for (var i = 0; i < 5; i++) {
          await $.tester.tap(version);
          await $.tester.pump(const Duration(milliseconds: 70));
        }
        await $.pumpAndSettle();
        expect(find.byType(CoffeeMazePage), findsOneWidget);
        await $.takeNativeScreenshot('holy-munch-ready');
        await $.tester.tap(find.byKey(const ValueKey('maze-start')));
        for (var i = 0; i < 20; i++) {
          await $.tester.pump(const Duration(milliseconds: 16));
        }
        final game = $.tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<CoffeeMazePainter>()
            .single
            .game;
        expect(game.phase, MazePhase.playing);
        expect(game.score, greaterThan(0));
        await $.takeNativeScreenshot('holy-munch-playing');
        await $.platform.mobile.pressHome();
        await $.platform.mobile.openApp();
        await $.pumpAndSettle();
        expect(game.phase, MazePhase.paused);
        final position = (game.player.x, game.player.y, game.caffeine);
        await $.tester.pump(const Duration(milliseconds: 500));
        expect((game.player.x, game.player.y, game.caffeine), position);
        await $.takeNativeScreenshot('holy-munch-paused');
        await $.tester.tap(find.byKey(const ValueKey('maze-start')));
        await $.tester.pump();
        expect(game.phase, MazePhase.playing);
        await $.tester.tap(find.byKey(const ValueKey('maze-pause')));
        await $.pumpAndSettle();
        await $.platform.android.pressBack();
        await $.pumpAndSettle();
        expect(find.byType(CoffeeMazePage), findsNothing);
        expect(version, findsOneWidget);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
      }
    },
  );
}
