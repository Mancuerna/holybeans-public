import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/grinder_consumption.dart';

void main() {
  test('a grinder card sums its brews and usual setting per method', () {
    ({String method, String? setting, int brewedAtMs}) brew(
      String method,
      String? setting,
      int at,
    ) => (method: method, setting: setting, brewedAtMs: at);
    final use = grinderUse([
      brew('Meticulous', '0.5', 1),
      brew('Meticulous', '0.6', 2),
      brew('Meticulous', '0.5', 3),
      brew('Origami S', '7.5', 4),
      brew('Origami S', '8', 5),
      brew('V60', null, 6),
    ]);
    expect(use.brewCount, 6);
    expect(use.lastBrewedAtMs, 6);
    expect(use.usualSettings, [
      (method: 'Meticulous', setting: '0.5'),
      // A tie goes to the setting used last.
      (method: 'Origami S', setting: '8'),
    ]);
    expect(grinderUse(const []).brewCount, 0);
  });
}
