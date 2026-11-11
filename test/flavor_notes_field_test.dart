import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flavor_descriptors.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/flavor_note_chip.dart';
import 'package:holybeans/ui/core/flavor_note_labels.dart';
import 'package:holybeans/ui/core/flavor_notes_field.dart';

import 'helpers/ui_test_support.dart';

Future<void> showEditor(
  WidgetTester tester,
  TextEditingController controller, {
  String language = 'es',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(language),
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [FlavorNotesField(controller: controller)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final input = find.byKey(const ValueKey('coffee-flavor-profile'));

  testWidgets('comma, paste and Enter create chips; pending note is included', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await showEditor(tester, controller);
    await tester.enterText(
      input,
      'Peach, jazmin, melocotón, tarta de la abuela, cacao',
    );
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(3));
    expect(controller.text, 'melocotón, jazmín, tarta de la abuela, cacao');
    expect(tester.widget<TextFormField>(input).controller!.text, ' cacao');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(4));
    expect(tester.widget<TextFormField>(input).controller!.text, '');
    await tester.tap(find.byTooltip('Quitar jazmín'));
    await tester.pumpAndSettle();
    expect(controller.text, 'melocotón, tarta de la abuela, cacao');
    await tester.enterText(input, 'Honey');
    await tester.pumpAndSettle();
    expect(controller.text, 'melocotón, tarta de la abuela, cacao, miel');
    await tester.enterText(input, '');
    await tester.pumpAndSettle();
    expect(controller.text, 'melocotón, tarta de la abuela, cacao');
  });

  testWidgets(
    'select bilingual suggestion, duplicates excluded and all removable',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await showEditor(tester, controller, language: 'en');
      await tester.enterText(input, 'albar');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'apricot'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'apricot'));
      await tester.pumpAndSettle();
      expect(controller.text, 'apricot');
      await tester.enterText(input, 'albar');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'apricot'), findsNothing);
      await tester.enterText(input, '');
      await tester.tap(find.byTooltip('Remove apricot'));
      await tester.pumpAndSettle();
      expect(controller.text, '');
    },
  );

  testWidgets(
    'opening, rebuilding, locale and external updates preserve raw storage',
    (tester) async {
      const raw = ' Peach , JASMINE, lemon cake, durazno ';
      final controller = TextEditingController(text: raw);
      addTearDown(controller.dispose);
      await showEditor(tester, controller);
      expect(
        tester.getCenter(find.text('Notas de cata')).dy,
        lessThan(tester.getTopLeft(find.text('Añadir una nota')).dy),
      );
      expect(controller.text, raw);
      expect(find.widgetWithText(InputChip, 'melocotón'), findsNWidgets(2));
      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(controller.text, raw);
      await showEditor(tester, controller, language: 'en');
      expect(controller.text, raw);
      expect(find.widgetWithText(InputChip, 'peach'), findsNWidgets(2));
      controller.text = 'miel, cacao';
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'honey'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'cocoa'), findsOneWidget);
      expect(controller.text, 'miel, cacao');
      await tester.enterText(input, 'Honey,');
      await tester.pumpAndSettle();
      expect(controller.text, 'miel, cacao');
    },
  );

  testWidgets('replacing parent controller reads the new imported profile', (
    tester,
  ) async {
    final first = TextEditingController(text: 'Peach');
    final second = TextEditingController(text: 'Rose, custom');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await showEditor(tester, first);
    await showEditor(tester, second);
    expect(find.widgetWithText(InputChip, 'rosa'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'melocotón'), findsNothing);
    first.text = 'lemon';
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'rosa'), findsOneWidget);
    expect(second.text, 'Rose, custom');
  });

  for (final language in ['es', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'narrow large-text editor and saved chips ($language, $brightness)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = TextEditingController(
            text: 'dark chocolate, jasmine, ${'long personal note ' * 8}',
          );
          addTearDown(controller.dispose);
          await showEditor(
            tester,
            controller,
            language: language,
            brightness: brightness,
            textScale: 1.5,
          );
          expect(tester.takeException(), isNull);
          final context = tester.element(input);
          final s = AppLocalizations.of(context);
          for (final descriptor in FlavorDescriptor.values) {
            expect(
              descriptor.aliases.any((alias) => alias == descriptor.label(s)),
              isTrue,
              reason: descriptor.name,
            );
          }
          await tester.enterText(input, 'choc');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final chips = tester.widgetList<FlavorNoteChip>(
            find.byType(FlavorNoteChip),
          );
          expect(chips.first.note, 'dark chocolate');
          await tester.pumpWidget(
            localizedApp(
              locale: Locale(language),
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FlavorNotes(profile: controller.text, maxNotes: 2),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('+2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
