import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/equipment/equipment_forms.dart';
import 'package:patrol/patrol.dart';

import '../test/helpers/gaggimate_fixture.dart';
import 'support/smoke_support.dart';

void main() {
  patrolTest(
    'configures Gaggimate and imports a completed recording over GET',
    tags: ['android', 'gaggimate'],
    ($) async {
      final db = await openTestDatabase();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        switch (request.uri.path) {
          case '/api/history/index.bin':
            request.response.add(gaggimateIndex());
          case '/api/history/000031.slog':
            request.response.add(gaggimateLog());
          case '/api/history/000031.json':
            request.response.headers.contentType = ContentType.html;
            request.response.write('<!doctype html><html>Gaggimate</html>');
          case '/api/history/31.json':
            request.response.write('{"doseIn":"18","grindSetting":"2.1"}');
          default:
            request.response.statusCode = 404;
        }
        await request.response.close();
      });
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        await repo.createCoffee(
          name: 'Gaggimate test beans',
          roaster: 'Test',
          initialGrams: 250,
        );
        await $.pumpWidgetAndSettle(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showMethodForm(context, repo),
                  child: const Text('Configure'),
                ),
              ),
            ),
          ),
        );
        await $.tap(find.text('Configure'));
        await $.enterText(
          find.widgetWithText(TextFormField, 'Method name'),
          'Gaggia test',
        );
        await $.tap(find.byKey(const ValueKey('method-machine')));
        await $.tap(find.text('Gaggimate').last);
        final address = find.byKey(const ValueKey('method-machine-address'));
        await $.scrollUntilVisible(
          finder: address,
          view: verticalScrollable(find.byType(BottomSheet).last),
        );
        await $.enterText(address, '127.0.0.1:${server.port}');
        await $.scrollUntilVisible(
          finder: find.byKey(const ValueKey('method-machine-test')),
          view: verticalScrollable(find.byType(BottomSheet).last),
        );
        await $.tap(find.byKey(const ValueKey('method-machine-test')));
        await $.waitUntilVisible(find.textContaining('Connected. Last shot:'));
        await $.takeNativeScreenshot('gaggimate-connection');
        await $.tap(find.text('Save').last);
        expect((await repo.allMethods()).single.machine, 'gaggimate');
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            services: AppServices(database: db),
            initialLocale: const Locale('en'),
          ),
        );
        await $.tap(find.text('Brew').last);
        final method = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Choose a method',
        );
        await $.scrollUntilVisible(
          finder: method,
          view: verticalScrollable(find.byType(BrewForm)),
        );
        await $.tap(method);
        await $.tap(find.text('Gaggia test').last);
        final importButton = find.byKey(
          const ValueKey('brew-import-gaggimate'),
        );
        await $.scrollUntilVisible(
          finder: importButton,
          view: verticalScrollable(find.byType(BrewForm)),
        );
        await $.tap(importButton);
        await $.waitUntilVisible(
          find.byKey(const ValueKey('gaggimate-shot-31')),
        );
        await $.takeNativeScreenshot('gaggimate-history');
        await $.tap(find.byKey(const ValueKey('gaggimate-shot-31')));
        await $.waitUntilVisible(find.text('Café test').first);
        await $.takeNativeScreenshot('gaggimate-imported');
        await $.tap(find.text('Save').last);
        final brew = (await repo.allBrews()).single;
        expect(
          (brew.doseGrams, brew.beverageGrams, brew.timeSeconds),
          (18.0, 36.5, 30),
        );
        expect((brew.firstDripSeconds, brew.pressureBar), (4, 9.0));
        expect((await repo.brewCurve(brew.id))!.source, 'gaggimate');
        expect(await repo.importedGaggimateShots(), hasLength(1));
        expect(requests, [
          'GET /api/history/index.bin',
          'GET /api/history/index.bin',
          'GET /api/history/000031.slog',
          'GET /api/history/000031.json',
          'GET /api/history/31.json',
        ]);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await server.close(force: true);
        await db.close();
      }
    },
  );
}
