import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/bean_exchange.dart';

void main() {
  const bean = SharedBean(
    name: 'Peña “Familia” ☕ 👩‍🌾 [2026] "A" \\ lote',
    roaster: 'Tostador\nSegunda línea',
    flavorNotes: ['Crème brûlée', '花', 'a_b *c* #1'],
    shopUrl: 'https://example.com/a_b?q=1&lot=2',
    bagGrams: 125.5,
    priceCents: 1234,
    roastDate: '2024-02-29',
  );
  for (final wrapper in ['file', 'code', 'qr']) {
    test(
      'valid $wrapper preserves Unicode, JSON escapes and numeric values',
      () {
        final json = encodeBeans([bean]);
        final source = switch (wrapper) {
          'code' => 'Ficha:\n```json\n$json\n```\nFin.',
          'qr' => beanQrText(bean),
          _ => json,
        };
        final result = readBeans(source).single;
        expect(result.dropped, isEmpty);
        expect(result.bean.toJson(), bean.toJson());
      },
    );
  }

  test('malformed inputs fail with a controlled reader error', () {
    for (final input in [
      '',
      'Un café lavado de Colombia',
      '{"name":',
      '{"name":"Lot \\q"}',
      'null',
      '42',
      '[]',
      '{"beans":[null,true,42,{"name":false}]}',
      '${beanQrPrefix}invalid',
      '{"version":99,"beans":[{"name":"Future"}]}',
    ]) {
      expect(
        () => readBeans(input),
        throwsA(isA<BeanReadException>()),
        reason: input,
      );
    }
  });

  test('optional fields are not guessed and invalid values are reported', () {
    final result = readBeans('''{"name":"Minimal","price":-1,
      "bagGrams":"unknown","roastDate":"tomorrow",
      "shopUrl":"javascript:alert(1)","roastLevel":"burnt"}''').single;
    expect(result.bean.roaster, isEmpty);
    expect(result.bean.priceCents, isNull);
    expect(result.bean.bagGrams, isNull);
    expect(result.bean.roastDate, isNull);
    expect(result.bean.shopUrl, isNull);
    expect(
      result.dropped,
      unorderedEquals([
        'price',
        'bagGrams',
        'roastDate',
        'shopUrl',
        'roastLevel',
      ]),
    );
  });
}
