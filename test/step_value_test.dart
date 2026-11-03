import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/step_value.dart';

void main() {
  test('a step follows the last digit written and keeps its form', () {
    expect(stepNumberText('0.5', 1), '0.6');
    expect(stepNumberText('0.5', -1), '0.4');
    expect(stepNumberText('7,5', 1), '7,6');
    expect(stepNumberText('18', 1), '19');
    expect(stepNumberText('18', -1), '17');
  });

  test('a given step rounds to its grid and drops needless zeros', () {
    expect(stepNumberText('23', 1, step: 0.1), '23.1');
    expect(stepNumberText('23.25', 1, step: 0.1), '23.3');
    expect(stepNumberText('90', 1, step: 1), '91');
    expect(stepNumberText('18.0', -1, step: 0.1), '17.9');
  });

  test('an empty field starts from zero and nothing goes below it', () {
    expect(stepNumberText('', 1, step: 0.1), '0.1');
    expect(stepNumberText('0', -1), '0');
    expect(stepNumberText('0.1', -1, step: 0.5), '0');
  });

  test('text that is not a plain number is left alone', () {
    expect(stepNumberText('18 clicks', 1), isNull);
    expect(stepNumberText('2.1.3', 1), isNull);
    expect(stepNumberText('-3', 1), isNull);
  });
}
