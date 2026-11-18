import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/settings/scale_section.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'settings group sharing and open devices separately without connecting',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final scale = FakeScale();
      addTearDown(scale.dispose);
      await tester.pumpWidget(
        localizedApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          home: SettingsPage(
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
            onExportBackup: () async {},
            onExportCsv: () {},
            onImportBackup: () async {},
            services: AppServices.forPreferences(
              BrewParameterSettings(db),
              templateSettings: ShareTemplateSettings(db),
              scale: scale,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brewing and journal'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-scale')), findsNothing);
      expect(find.text('No paired devices'), findsOneWidget);
      scale
        ..name = 'BOOKOO'
        ..status = DeviceStatus.bluetoothOff
        ..notifyListeners();
      await tester.pump();
      expect(find.text('1 paired · Bluetooth off'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-devices')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scale-find')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-scale')));
      await tester.pumpAndSettle();
      expect(find.byType(ScaleSection), findsOneWidget);
      expect(scale.commands, isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-preparation')));
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
