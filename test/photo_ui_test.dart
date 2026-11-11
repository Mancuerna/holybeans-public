import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('bean photos show in cards and details and can be removed', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('holybeans-photo-ui'),
    ))!;
    addTearDown(() => temp.deleteSync(recursive: true));
    final photos = PhotoStore(Directory('${temp.path}/photos'));
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Pictured bean',
      roaster: 'Test roaster',
    );
    final name = (await tester.runAsync(
      () => photos.add(Uint8List.fromList(List.filled(64, 7))),
    ))!;
    await repository.setCoffeePhotos(coffeeId, [name]);

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database, photos: photos),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('bean-thumb-$coffeeId')), findsOneWidget);

    await tester.tap(find.text('Pictured bean'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-photo')), findsOneWidget);
    await tester.tap(find.byTooltip('Edit bean'));
    await tester.pumpAndSettle();

    final remove = find.byKey(ValueKey('remove-photo-$name'));
    await tester.scrollUntilVisible(
      remove,
      240,
      scrollable: find
          .descendant(
            of: find.byType(CoffeeForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-photo')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Save').last);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(await repository.coffeePhotos(coffeeId), isEmpty);
    expect(photos.file(name).existsSync(), isFalse);
    expect(find.byKey(ValueKey('bean-thumb-$coffeeId')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  for (final reduced in [false, true]) {
    testWidgets('photo dots respect reduced motion: $reduced', (tester) async {
      await tester.pumpWidget(
        localizedApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: DetailPhotos(
            store: PhotoStore(Directory.systemTemp),
            files: const [
              '00000000-0000-0000-0000-000000000001.jpg',
              '00000000-0000-0000-0000-000000000002.jpg',
            ],
            label: 'Bean photos',
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
            .duration,
        reduced ? Duration.zero : const Duration(milliseconds: 200),
      );
    });
  }
}
