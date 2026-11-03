/// What a launcher shortcut (long press on the app icon) asks for. Each
/// opens the app with a `holybeans://shortcut/<name>` link.
enum AppShortcut {
  /// A new brew, starting from the last usable one like the Brew button.
  brew,

  /// The last brew again, as Repeat does.
  repeat,

  /// A coffee card from a QR code.
  scanBean,

  /// Only opens the app, e.g. tapping the widget outside its buttons.
  open;

  static const _prefix = 'holybeans://shortcut/';

  /// The shortcut a link stands for, or null when it is not one (a coffee
  /// card link, a shared text) or names one this version does not know.
  static AppShortcut? fromLink(String text) {
    final link = text.trim();
    if (!link.startsWith(_prefix)) return null;
    final name = link.substring(_prefix.length).split(RegExp('[/?#]')).first;
    return switch (name) {
      'brew' => AppShortcut.brew,
      'repeat' => AppShortcut.repeat,
      'scan-bean' => AppShortcut.scanBean,
      'open' => AppShortcut.open,
      _ => null,
    };
  }
}
