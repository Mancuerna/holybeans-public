import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/fake_scale.dart';

void main() {
  testWidgets(
    'settings group sharing and open devices separately without connecting',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final scale = FakeScale();
      addTearDown(scale.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
            onExportBackup: () {},
            onExportCsv: () {},
            onImportBackup: () {},
            parameterSettings: BrewParameterSettings(db),
            templateSettings: ShareTemplateSettings(db),
            scale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brewing and sharing'), findsOneWidget);
      expect(find.byKey(const ValueKey('scale-find')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-scale')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scale-find')), findsOneWidget);
      expect(scale.commands, isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-templates')));
      await tester.pumpAndSettle();
      expect(find.byType(ShareTemplatesPage), findsOneWidget);
      expect(
        find.text('No templates. Sharing keeps the field format.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
