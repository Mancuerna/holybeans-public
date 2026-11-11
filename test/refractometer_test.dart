import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/domain/difluid_r2_protocol.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/settings/refractometer_section.dart';

import 'helpers/fake_refractometer.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

/// A frame from the R2: header, Device Action, [command], data, checksum.
List<int> _frame(int command, List<int> data) => difluidFrame(3, command, data);

void main() {
  Widget app(Widget home) =>
      localizedApp(locale: const Locale('en'), home: home);

  test('the R2 is asked to measure with the documented frame and its '
      'reports are read', () {
    // As in DiFluid's protocol document.
    expect(difluidSingleTest, [0xdf, 0xdf, 0x03, 0x00, 0x00, 0xc1]);
    expect(difluidGetNumberOfTests, [0xdf, 0xdf, 0x01, 0x03, 0x00, 0xc2]);
    expect(difluidAverageTest(3), [0xdf, 0xdf, 0x03, 0x01, 0x01, 0x03, 0xc6]);
    expect(
      (parseR2Message([0xdf, 0xdf, 0x01, 0x03, 0x01, 0x03, 0xc6])!
              as R2TestCount)
          .count,
      3,
    );
    // The document's average test: started, then the mean, -0.07 %.
    expect(
      parseR2Message([0xdf, 0xdf, 0x03, 0x01, 0x03, 0x00, 0x04, 0x00, 0xc9]),
      isA<R2Measuring>(),
    );
    expect(
      parseR2Message([
        0xdf, 0xdf, 0x03, 0x01, 0x07, 0x03, 0xff, 0xf9, 0xff, 0xff, 0xe4, //
        0x44, 0xea,
      ]),
      isA<R2Result>().having((result) => result.tdsPercent, 'TDS', -0.07),
    );
    // A reading on the way to the mean is not the result.
    expect(
      parseR2Message([
        0xdf, 0xdf, 0x03, 0x01, 0x07, 0x02, 0xff, 0xf9, 0x00, 0x02, 0x08, //
        0xa6, 0x73,
      ]),
      isNull,
    );
    expect(isDifluidR2Name('R2 Extract'), isTrue);
    expect(isDifluidR2Name('BOOKOO_SC_U'), isFalse);

    expect(parseR2Message(_frame(0, [0, 11])), isA<R2Measuring>());
    // 0x01 0x2C = 300: 3.00 % TDS; the refractive index follows.
    final result = parseR2Message(_frame(0, [2, 0x01, 0x2c, 0, 2, 0, 0]));
    expect((result! as R2Result).tdsPercent, 3.0);
    // An average test reports its mean, not each reading on the way.
    expect(parseR2Message(_frame(1, [2, 0x01, 0x2c])), isNull);
    expect(
      (parseR2Message(_frame(1, [3, 0x00, 0x8f]))! as R2Result).tdsPercent,
      1.43,
    );
    expect(
      (parseR2Message(_frame(254, [0, 2, 3]))! as R2Failed).noLiquid,
      isTrue,
    );
    // Temperatures, a wrong checksum or a broken frame are left out.
    expect(parseR2Message(_frame(0, [1, 3, 0x17, 3, 0x10, 0])), isNull);
    final corrupt = _frame(0, [2, 0x01, 0x2c])..last ^= 1;
    expect(parseR2Message(corrupt), isNull);
    expect(parseR2Message([0xdf, 0xdf, 3]), isNull);
  });

  testWidgets('settings find and pair a refractometer', (tester) async {
    final refractometer = FakeRefractometer(
      nearby: const [FoundDevice(id: 'R2:01', name: 'R2 Extract')],
    );
    addTearDown(refractometer.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: RefractometerSection(refractometer: refractometer),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('refractometer-find')));
    await tester.pump();
    expect(find.text('R2 Extract'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(refractometer.connected, isTrue);
    refractometer.emit(const R2Result(1.38));
    await tester.pump();
    expect(find.text('TDS 1.38 %'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('refractometer-forget')));
    await tester.pump();
    expect(refractometer.name, isNull);
  });

  testWidgets('the TDS measures with the connected refractometer and takes '
      'readings made with its own button', (tester) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'TDS coffee', roaster: 'R');
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffees = await database.select(database.coffees).get();
    final refractometer = FakeRefractometer(name: 'R2 Extract');
    addTearDown(refractometer.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: BrewForm(
            services: AppServices.forJournal(
              repository,
              parameterSettings: BrewParameterSettings(database),
              refractometer: refractometer,
            ),

            coffees: coffees,
            initialMethodId: methodId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    final tds = find.widgetWithText(TextFormField, 'TDS (%)');
    await tester.scrollUntilVisible(tds, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    final measure = find.byKey(const ValueKey('refractometer-measure'));
    expect(measure, findsNothing, reason: 'not connected yet');

    await refractometer.connect();
    await tester.pump();
    expect(measure, findsOneWidget);
    await tester.tap(measure);
    await tester.pump();
    expect(refractometer.measures, 1);
    expect(tester.widget<IconButton>(measure).onPressed, isNull);
    refractometer.emit(const R2Result(1.42));
    await tester.pump();
    String text() => tester.widget<TextFormField>(tds).controller!.text;
    expect(text(), '1.42');

    // Measured with the R2's own button: the reading is taken too.
    refractometer.emit(const R2Failed(noLiquid: true));
    await tester.pump();
    expect(
      find.text("Couldn't measure. Is there a sample on the prism?"),
      findsOneWidget,
    );
    refractometer
      ..emit(const R2Measuring())
      ..emit(const R2Result(1.5));
    await tester.pump();
    expect(text(), '1.5');
    expect(
      find.text("Couldn't measure. Is there a sample on the prism?"),
      findsNothing,
    );

    // Water or an empty prism reads below zero: said, not noted.
    refractometer.emit(const R2Result(-0.14));
    await tester.pump();
    expect(text(), '1.5');
    expect(
      find.text(
        'Read -0.14 %, below zero (water or an empty prism): not noted.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
