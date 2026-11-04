import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/text_suggestions.dart';

import 'support/search_prototype.dart';

void main() {
  test('allocation prototype preserves existing text folding', () {
    const symbols = [
      'áàäâãéèëêíìïîóòöôõúùüûñç',
      'ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
      'cafe\u0301',
      'CAFÉ',
      '🙂',
      '\t',
      '\n',
      ' ',
      '\u00a0',
      'İ',
      'ß',
      '漢字',
      '\u0300',
      '\u036f',
      '\u0370',
      'V60',
      '  North   roaster  ',
      '',
      'plain ASCII text',
    ];
    for (final value in symbols) {
      expect(foldWithoutCharacterList(value), foldSuggestion(value));
    }
    final random = Random(42);
    for (var i = 0; i < 1000; i++) {
      final text = List.generate(
        30,
        (_) => symbols[random.nextInt(symbols.length)],
      ).join();
      expect(foldWithoutCharacterList(text), foldSuggestion(text));
      final prefix = symbols[random.nextInt(symbols.length)];
      final full = foldSuggestion('$prefix $text');
      for (final query in [
        foldSuggestion(prefix),
        foldSuggestion(text).substring(0, min(12, foldSuggestion(text).length)),
        full.substring(0, min(20, full.length)),
        'not-present-needle',
      ]) {
        expect(metadataFirstMatches(prefix, text, query), full.contains(query));
      }
    }
  });
}
