import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/profile_suggestions.dart';

void main() {
  test('prefers the selected method, then recency, across coffees', () {
    final suggestions = ProfileSuggestions([
      (name: 'Plano antiguo', methodId: 'a', brewedAtMs: 10),
      (name: 'Plano reciente', methodId: 'a', brewedAtMs: 20),
      (name: 'Otro reciente', methodId: 'b', brewedAtMs: 40),
      (name: 'Sin método', methodId: null, brewedAtMs: 30),
    ]);
    expect(suggestions.forMethod('a'), [
      'Plano reciente',
      'Plano antiguo',
      'Otro reciente',
      'Sin método',
    ]);
    expect(suggestions.forMethod('b'), [
      'Otro reciente',
      'Sin método',
      'Plano reciente',
      'Plano antiguo',
    ]);
    expect(suggestions.forMethod(null), suggestions.forMethod('unknown'));
    expect(suggestions.forMethod(null).first, 'Otro reciente');
  });

  test('deduplicates accents/case/spaces and preserves preferred spelling', () {
    final suggestions = ProfileSuggestions([
      (name: '  Plano sin preinfusión  ', methodId: 'a', brewedAtMs: 10),
      (name: 'PLANO   SIN PREINFUSION', methodId: 'b', brewedAtMs: 20),
      (name: 'Plano sin preinfusio\u0301n', methodId: null, brewedAtMs: 5),
      (name: '  ', methodId: 'a', brewedAtMs: 100),
    ]);
    expect(suggestions.forMethod('a'), ['Plano sin preinfusión']);
    expect(suggestions.forMethod(null), ['PLANO   SIN PREINFUSION']);
    expect(ProfileSuggestions([]).forMethod('a'), isEmpty);
  });
}
