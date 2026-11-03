import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareClipboard {
  const ShareClipboard();

  static const _channel = MethodChannel('holybeans/share-clipboard');

  bool get supportsImages =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> copyImage(Uint8List png) async {
    if (!supportsImages) throw UnsupportedError('Image clipboard unavailable');
    await _channel.invokeMethod<void>('copyImage', png);
  }
}
