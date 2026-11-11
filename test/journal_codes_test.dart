import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/journal_codes.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/ui/beans/freezer_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';

void main() {
  test('roast codes keep their stored spelling and darkest-first order', () {
    expect(beanRoastLevels, ['dark', 'medium', 'omni', 'light', 'ultra_light']);
    expect(RoastLevel.fromCode('ultra_light'), RoastLevel.ultraLight);
    expect(RoastLevel.fromCode('ULTRA_LIGHT'), isNull);
    expect(RoastLevel.fromCode(null), isNull);
    expect(() => validateRoastLevel('unknown'), throwsArgumentError);
    expect(() => validateRoastLevel(null), returnsNormally);
    expect(roastLevelLabel(AppLocalizationsEn(), 'unknown'), 'unknown');
  });

  test(
    'method legacy alias is opt-in and espresso fallback remains null-only',
    () {
      expect(MethodCategory.values.map((v) => v.code), [
        'espresso',
        'pourover',
        'immersion',
      ]);
      expect(MethodCategory.fromCode('percolation'), isNull);
      expect(
        MethodCategory.fromCode('percolation', allowLegacy: true),
        MethodCategory.pourover,
      );
      expect(
        isEspressoMethod(category: ' ESPRESSO ', methodName: 'other'),
        isTrue,
      );
      expect(isEspressoMethod(category: null, methodName: 'Espresso'), isTrue);
      expect(isEspressoMethod(category: '', methodName: 'Espresso'), isFalse);
      expect(
        isEspressoMethod(category: 'unknown', methodName: 'Espresso'),
        isFalse,
      );
    },
  );

  test('container codes preserve ordering, validation and unknown labels', () {
    expect(allowedFrozenContainers, [
      'vacuum_bag',
      'tube',
      'zip_bag',
      'jar',
      'container',
      'original_bag',
      'other',
    ]);
    expect(
      FrozenContainer.fromCode('original_bag'),
      FrozenContainer.originalBag,
    );
    expect(FrozenContainer.fromCode('other'), FrozenContainer.other);
    expect(FrozenContainer.fromCode('UNKNOWN'), isNull);
    expect(() => validateFrozenContainer('UNKNOWN'), throwsArgumentError);
    expect(() => validateFrozenContainer(null), returnsNormally);
    expect(frozenContainerLabel(AppLocalizationsEn(), 'UNKNOWN'), '');
  });
}
