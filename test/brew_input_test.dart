import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_input.dart';

void main() {
  test('an incomplete recipe and supported boundary values remain valid', () {
    BrewInput(coffeeId: 'coffee', methodName: ' V60 ').validate();
    for (final rating in [0.0, 0.5, 9.5, 10.0]) {
      BrewInput(
        coffeeId: 'coffee',
        methodName: 'Espresso',
        rating: rating,
        pressureBar: 30,
        tdsPercent: 100,
        temperatureC: 0,
      ).validate();
    }
    BrewInput(
      coffeeId: 'coffee',
      methodName: 'Espresso',
      pressureBar: 0,
    ).validate();
  });

  test('invalid recipe values fail without a database', () {
    final invalid = [
      BrewInput(coffeeId: 'c', methodName: ' '),
      BrewInput(coffeeId: 'c', methodName: 'V60', doseGrams: 0),
      BrewInput(coffeeId: 'c', methodName: 'V60', waterGrams: -1),
      BrewInput(coffeeId: 'c', methodName: 'V60', beverageGrams: double.nan),
      BrewInput(coffeeId: 'c', methodName: 'V60', timeSeconds: 0),
      BrewInput(
        coffeeId: 'c',
        methodName: 'V60',
        temperatureC: double.infinity,
      ),
      BrewInput(coffeeId: 'c', methodName: 'V60', tdsPercent: 0),
      BrewInput(coffeeId: 'c', methodName: 'V60', tdsPercent: 101),
      BrewInput(coffeeId: 'c', methodName: 'V60', grindRpm: 0),
      BrewInput(coffeeId: 'c', methodName: 'V60', preinfusionSeconds: -1),
      BrewInput(coffeeId: 'c', methodName: 'V60', bloomSeconds: 0),
      BrewInput(coffeeId: 'c', methodName: 'V60', firstDripSeconds: 0),
      BrewInput(coffeeId: 'c', methodName: 'V60', pressureBar: -0.1),
      BrewInput(coffeeId: 'c', methodName: 'V60', pressureBar: 31),
      BrewInput(coffeeId: 'c', methodName: 'V60', pressureBar: double.nan),
      BrewInput(coffeeId: 'c', methodName: 'V60', rating: 7.3),
      BrewInput(coffeeId: 'c', methodName: 'V60', rating: double.nan),
      BrewInput(coffeeId: 'c', methodName: 'V60', rating: -0.5),
      BrewInput(coffeeId: 'c', methodName: 'V60', rating: 10.5),
    ];
    for (final input in invalid) {
      expect(input.validate, throwsArgumentError);
    }
  });

  test(
    'pre-ground coffee accepts no grinder, including blank legacy names',
    () {
      BrewInput(
        coffeeId: 'c',
        methodName: 'V60',
        isPreGround: true,
        grinderName: ' ',
      ).validate();
      for (final input in [
        BrewInput(
          coffeeId: 'c',
          methodName: 'V60',
          isPreGround: true,
          grinderId: 'g',
        ),
        BrewInput(
          coffeeId: 'c',
          methodName: 'V60',
          isPreGround: true,
          grinderName: 'G',
        ),
      ]) {
        expect(input.validate, throwsArgumentError);
      }
    },
  );

  test('tools are a snapshot and distinguish retaining from clearing', () {
    final tools = ['paper'];
    final input = BrewInput(
      coffeeId: 'c',
      methodName: 'V60',
      methodToolIds: tools,
    );
    tools.clear();
    expect(input.methodToolIds, ['paper']);
    expect(() => input.methodToolIds!.add('filter'), throwsUnsupportedError);
    expect(BrewInput(coffeeId: 'c', methodName: 'V60').methodToolIds, isNull);
    expect(
      BrewInput(
        coffeeId: 'c',
        methodName: 'V60',
        methodToolIds: [],
      ).methodToolIds,
      isEmpty,
    );
  });
}
