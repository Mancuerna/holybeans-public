import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/text_suggestions.dart';

void main() {
  test(
    'suggestions match accents and whitespace without changing spellings',
    () {
      expect(foldSuggestion('  Edwin   Noreña '), 'edwin norena');
      expect(foldSuggestion('Noren\u0303a'), 'norena');
      expect(
        uniqueSuggestions([
          ' Edwin Noreña ',
          'edwin norena',
          null,
          '',
          '  ',
          'Ana',
        ]),
        ['Ana', 'Edwin Noreña'],
      );
    },
  );
}
