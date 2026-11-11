import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/coffee_maze_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/domain/coffee_maze.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_page.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_painter.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

class MemoryMazeSettings extends CoffeeMazeSettings {
  MemoryMazeSettings() : super(File('unused'));
  int best = 120;

  @override
  Future<int> readBest() async => best;

  @override
  Future<void> saveBest(int score) async {
    if (score > best) best = score;
  }
}

Widget app(Widget home, {String language = 'en', double textScale = 1}) =>
    localizedApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: Locale(language),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

CoffeeMaze gameOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<CoffeeMazePainter>()
    .single
    .game;

void main() {
  testWidgets('five quick version taps reveal one game; spaced taps reset', (
    tester,
  ) async {
    const device = MethodChannel('holybeans/device');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      device,
      (call) async => call.method == 'appVersion' ? '1.4.1 (162)' : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        device,
        null,
      ),
    );
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      app(
        SettingsPage(
          locale: const Locale('en'),
          onLocaleChanged: (_) {},
          onExportBackup: () async {},
          onExportCsv: () {},
          onImportBackup: () async {},
          parameterSettings: BrewParameterSettings(db),
          templateSettings: ShareTemplateSettings(db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final version = find.byKey(const ValueKey('app-version'));
    await tester.scrollUntilVisible(version, 400);
    for (var i = 0; i < 4; i++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byType(CoffeeMazePage), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(version);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(CoffeeMazePage), findsNothing);
    for (var i = 0; i < 4; i++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeMazePage), findsOneWidget);
    expect(gameOf(tester).phase, MazePhase.ready);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeMazePage), findsNothing);
    expect(version, findsOneWidget);
    await tester.tap(version);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swipes, buttons and keys steer; backgrounding pauses until resumed',
    (tester) async {
      final store = MemoryMazeSettings();
      await tester.pumpWidget(app(CoffeeMazePage(settings: () async => store)));
      await tester.pumpAndSettle();
      expect(find.text('0120'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('maze-start')));
      await tester.pump();
      final game = gameOf(tester);
      expect(game.phase, MazePhase.playing);
      await tester.tap(find.byKey(const ValueKey('maze-up')));
      expect(game.queuedDirection, MazeDirection.up);
      await tester.drag(
        find.byKey(const ValueKey('maze-board')),
        const Offset(60, 0),
      );
      expect(game.queuedDirection, MazeDirection.right);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(game.queuedDirection, MazeDirection.left);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(game.phase, MazePhase.paused);
      expect(tester.binding.hasScheduledFrame, isFalse);
      final x = game.player.x;
      await tester.pump(const Duration(seconds: 5));
      expect(game.player.x, x);
      await tester.tap(find.byKey(const ValueKey('maze-start')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(game.phase, MazePhase.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(game.phase, MazePhase.paused);
      game.score = 700;
      await tester.tap(find.byKey(const ValueKey('maze-start')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('maze-pause')));
      await tester.pumpAndSettle();
      expect(store.best, 700);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits $size with text scale $scale in Spanish', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          app(
            CoffeeMazePage(settings: () async => MemoryMazeSettings()),
            language: 'es',
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A por los granos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final board = tester.getSize(find.byKey(const ValueKey('maze-board')));
        expect(board.width, greaterThan(0));
        expect(
          board.width / board.height,
          closeTo(CoffeeMaze.columns / CoffeeMaze.rows, .001),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('maze-start')));
        await tester.tap(find.byKey(const ValueKey('maze-start')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(gameOf(tester).phase, MazePhase.playing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('unavailable record storage still allows a round', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CoffeeMazePage(
          settings: () async {
            throw const FileSystemException('unavailable');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Record saving is unavailable.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('maze-start')));
    await tester.pump();
    expect(gameOf(tester).phase, MazePhase.playing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
