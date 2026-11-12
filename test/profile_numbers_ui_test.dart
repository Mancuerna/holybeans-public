import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/extraction_profile_repository.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/profiles/profile_editor_page.dart';
import 'package:holybeans/ui/profiles/profile_library_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('Spanish library uses caudal and localized compact numbers', (
    tester,
  ) async {
    final db = memoryDatabase();
    final repo = ExtractionProfileRepository(db);
    addTearDown(db.close);
    await repo.save(
      ExtractionProfile.example('p', 'Mi espresso').copyWith(doseGrams: 18.5),
    );
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('es'),
        home: ProfileLibraryPage(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Caudal y presión · 30 s · 18,5 g · 93 °C'),
      findsOneWidget,
    );
    expect(find.text('Peso previsto: 38 g'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  for (final locale in ['es', 'en']) {
    testWidgets(
      '$locale editor preserves numeric input precision and saves decimal input',
      (tester) async {
        ExtractionProfile? saved;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(locale),
            home: ProfileEditorPage(
              profile: ExtractionProfile.example(
                'p',
                'Example',
              ).copyWith(doseGrams: 18.125),
              onSave: (p) async {
                saved = p;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final fields = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .toList();
        expect(
          fields[1].controller!.text,
          locale == 'es' ? '18,125' : '18.125',
        );
        expect(fields[2].controller!.text, '93');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          locale == 'es' ? '19,25' : '19.25',
        );
        await tester.tap(find.text(locale == 'es' ? 'Guardar' : 'Save'));
        await tester.pumpAndSettle();
        expect(saved?.doseGrams, 19.25);
        expect(saved?.temperatureC, 93);
      },
    );
  }
}
