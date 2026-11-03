import 'package:flutter/services.dart';

/// Device credentials deliberately absent from journal preferences and backups.
abstract interface class LoffeeKeyStore {
  Future<String?> read();
  Future<void> save(String key);
  Future<void> delete();
}

class AndroidLoffeeKeyStore implements LoffeeKeyStore {
  const AndroidLoffeeKeyStore();
  static const _channel = MethodChannel('holybeans/loffee-key');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> save(String key) => _channel.invokeMethod<void>('save', key);

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}
