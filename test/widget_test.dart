import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/main.dart';

void main() {
  testWidgets('live journal has concise Spanish and English labels', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('No hay granos.'), findsOneWidget);
    expect(find.text('Tu café, a mano'), findsNothing);

    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-en')),
      300,
    );
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('No beans.'), findsOneWidget);
    expect(find.text('Coffee, at hand'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await database.close();
  });
}
