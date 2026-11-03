import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/equipment/piston/piston_credits.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  for (final language in ['es', 'en']) {
    testWidgets(
      'credits fit large text and open both original projects: $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final urls = <String>[];
        var available = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'launch') {
              urls.add((call.arguments as Map)['url'] as String);
              return available;
            }
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final s = lookupAppLocalizations(Locale(language));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: PistonCredits(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.pistonCredits), findsOneWidget);
        for (final project in ['ha-meticulous-cards', 'ha-meticulous']) {
          final button = find.byKey(ValueKey('piston-credit-$project'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(urls, [
          'https://github.com/cjborchert/ha-meticulous-cards',
          'https://github.com/cjborchert/ha-meticulous',
        ]);
        available = false;
        await tester.tap(
          find.byKey(const ValueKey('piston-credit-ha-meticulous')),
        );
        await tester.pumpAndSettle();
        expect(find.text(s.pistonProjectUnavailable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'About opens bundled author licences without version metadata: $language',
      (tester) async {
        final licences = await tester.runAsync(
          () => bundledAppLicenses().toList(),
        );
        LicenseRegistry.reset();
        LicenseRegistry.addLicense(() => Stream.fromIterable(licences!));
        addTearDown(LicenseRegistry.reset);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final s = lookupAppLocalizations(Locale(language));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsPage(
              locale: Locale(language),
              onLocaleChanged: (_) {},
              onExportBackup: () {},
              onExportCsv: () {},
              onImportBackup: () {},
              parameterSettings: BrewParameterSettings(db),
              templateSettings: ShareTemplateSettings(db),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('app-licenses'));
        await tester.scrollUntilVisible(entry, 400);
        expect(find.text(s.settingsAbout), findsOneWidget);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        final project = find.text('Meticulous piston analysis');
        await tester.scrollUntilVisible(project, 300);
        await tester.tap(project);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Copyright (c) 2026 hessius', findRichText: true),
          findsWidgets,
        );
        await tester.scrollUntilVisible(
          find.textContaining(
            'Copyright (c) 2026 Chris Borchert',
            findRichText: true,
          ),
          500,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
