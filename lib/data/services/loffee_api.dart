import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:holybeans/data/services/loffee_key_store.dart';
import 'package:holybeans/domain/loffee_bean.dart';

enum LoffeeFailure { authentication, rateLimit, network, unavailable, response }

/// Contains no server text or URL that could echo a credential into logs.
class LoffeeException implements Exception {
  const LoffeeException(this.failure);
  final LoffeeFailure failure;
  @override
  String toString() => 'LoffeeException(${failure.name})';
}

abstract interface class LoffeeApi {
  Future<LoffeePage> search({
    required String key,
    required String query,
    int page = 1,
  });
  Future<Uint8List> photo(String url);
}

class LoffeeServices {
  const LoffeeServices({required this.api, required this.keys});
  final LoffeeApi api;
  final LoffeeKeyStore keys;
}

/// Documented v2 GETs only. Authenticated redirects are never followed.
class LoffeeClient implements LoffeeApi {
  LoffeeClient({
    HttpClient Function()? clientFactory,
    Uri? baseUri,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _clientFactory = clientFactory ?? HttpClient.new,
       // The documented subdomain has no DNS record. The same documented
       // route on the official www host was verified with authenticated GET.
       _base = baseUri ?? Uri.https('www.loffeelabs.com', '/api/v2/beans');

  static const pageSize = 20;
  final HttpClient Function() _clientFactory;
  final Uri _base;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final Duration interval;
  final Duration timeout;
  Future<void> _queue = Future<void>.value();
  DateTime? _nextRequest;
  DateTime? _retryAfter;
  final _cache = <String, LoffeePage>{};
  String? _cacheKey;

  @override
  Future<LoffeePage> search({
    required String key,
    required String query,
    int page = 1,
  }) async {
    if (key.trim().isEmpty ||
        key.trim().length > 512 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(key.trim())) {
      throw const LoffeeException(LoffeeFailure.authentication);
    }
    final clean = query.trim();
    if (clean.isEmpty || page < 1) throw ArgumentError('Invalid search');
    if (_cacheKey != key) {
      _cache.clear();
      _cacheKey = key;
      _retryAfter = null;
    }
    final cacheId = '$clean\u0000$page';
    if (_cache[cacheId] case final cached?) return cached;
    final ready = Completer<void>();
    final previous = _queue;
    _queue = ready.future;
    var requested = false;
    try {
      await previous;
      if (_retryAfter?.isAfter(_clock()) ?? false) {
        throw const LoffeeException(LoffeeFailure.rateLimit);
      }
      final delay = _nextRequest?.difference(_clock());
      if (delay != null && delay > Duration.zero) {
        await _delay(delay);
      }
      final uri = _base.replace(
        queryParameters: {
          'search': clean,
          'page': '$page',
          'limit': '$pageSize',
        },
      );
      requested = true;
      final bytes = await _get(uri, key: key, maxBytes: 2 * 1024 * 1024);
      final result = LoffeePage.decode(
        jsonDecode(utf8.decode(bytes)),
        page: page,
        limit: pageSize,
      );
      if (_cacheKey == key) {
        if (_cache.length >= 12) _cache.remove(_cache.keys.first);
        _cache[cacheId] = result;
      }
      return result;
    } on FormatException {
      throw const LoffeeException(LoffeeFailure.response);
    } finally {
      // Wait after the response: different connection latencies must not
      // squeeze the interval between requests as observed by the server.
      if (requested) _nextRequest = _clock().add(interval);
      ready.complete();
    }
  }

  @override
  Future<Uint8List> photo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const LoffeeException(LoffeeFailure.response);
    }
    // Images never receive the API Authorization header.
    return _get(uri, maxBytes: 8 * 1024 * 1024, image: true);
  }

  Future<Uint8List> _get(
    Uri uri, {
    String? key,
    required int maxBytes,
    bool image = false,
  }) async {
    final client = _clientFactory();
    client.connectionTimeout = timeout;
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          image ? 'image/*' : 'application/json',
        );
        if (key != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${key.trim()}',
          );
        }
        final response = await request.close();
        switch (response.statusCode) {
          case 401:
          case 403:
            throw const LoffeeException(LoffeeFailure.authentication);
          case 429:
            final seconds = int.tryParse(
              response.headers.value('retry-after') ?? '',
            );
            final date = response.headers.value('retry-after');
            DateTime? until;
            if (seconds != null && seconds > 0) {
              until = _clock().add(Duration(seconds: seconds));
            }
            if (seconds == null && date != null) {
              try {
                until = HttpDate.parse(date);
              } on FormatException {
                /* Standard interval applies. */
              }
            }
            if (key != null && key == _cacheKey && until != null) {
              _retryAfter = until;
            }
            throw const LoffeeException(LoffeeFailure.rateLimit);
          case 200:
            break;
          default:
            throw const LoffeeException(LoffeeFailure.unavailable);
        }
        if (response.contentLength > maxBytes ||
            (image &&
                !(response.headers.contentType?.mimeType.startsWith('image/') ??
                    false))) {
          throw const LoffeeException(LoffeeFailure.response);
        }
        final result = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (result.length + chunk.length > maxBytes) {
            throw const LoffeeException(LoffeeFailure.response);
          }
          result.add(chunk);
        }
        return result.takeBytes();
      })().timeout(timeout);
    } on SocketException {
      throw const LoffeeException(LoffeeFailure.network);
    } on HandshakeException {
      throw const LoffeeException(LoffeeFailure.network);
    } on HttpException {
      throw const LoffeeException(LoffeeFailure.network);
    } on TimeoutException {
      throw const LoffeeException(LoffeeFailure.network);
    } finally {
      client.close(force: true);
    }
  }
}
