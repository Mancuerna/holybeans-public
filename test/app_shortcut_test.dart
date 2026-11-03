import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/app_shortcut.dart';

void main() {
  test('launcher shortcut links are told from coffee cards', () {
    expect(AppShortcut.fromLink('holybeans://shortcut/brew'), AppShortcut.brew);
    expect(
      AppShortcut.fromLink(' holybeans://shortcut/repeat '),
      AppShortcut.repeat,
    );
    expect(
      AppShortcut.fromLink('holybeans://shortcut/scan-bean?from=launcher'),
      AppShortcut.scanBean,
    );
    expect(AppShortcut.fromLink('holybeans://shortcut/open'), AppShortcut.open);
    expect(AppShortcut.fromLink('holybeans://shortcut/unknown'), isNull);
    expect(AppShortcut.fromLink('holybeans://bean?c=abc'), isNull);
    expect(AppShortcut.fromLink('Kenya, washed'), isNull);
  });
}
