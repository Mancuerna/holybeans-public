import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:holybeans/domain/gaggimate/binary.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';

enum GaggimateFailure { connection, unavailable, invalidData }

class GaggimateException implements Exception {
  const GaggimateException(this.failure, {this.reason});
  final GaggimateFailure failure;
  final String? reason;

  @override
  String toString() =>
      'GaggimateException(${failure.name}${reason == null ? '' : ': $reason'})';
}

abstract interface class GaggimateSource {
  String get machineAddress;
  Future<List<GaggimateHistoryEntry>> history();
  Future<GaggimateShot> shot(GaggimateHistoryEntry entry);
  void close();
}

GaggimateSource Function(String address) connectGaggimate = GaggimateClient.new;

/// Only documented GET history files. Redirects and machine commands are disabled.
class GaggimateClient implements GaggimateSource {
  GaggimateClient(String address, {HttpClient? httpClient})
    : base = normalizeAddress(address),
      _http = httpClient ?? HttpClient();

  final Uri base;
  final HttpClient _http;
  static const _timeout = Duration(seconds: 15);
  static const _maxBytes = 16 * 1024 * 1024;

  static Uri normalizeAddress(String address) {
    final text = address.trim();
    if (text.isEmpty) throw const FormatException('Empty address');
    final uri = Uri.parse(text.contains('://') ? text : 'http://$text');
    if (uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Invalid machine address');
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host.toLowerCase(),
      port: uri.port,
    );
  }

  @override
  String get machineAddress => base.toString();

  Future<Uint8List?> _get(String filename, {bool optional = false}) async {
    try {
      final request = await _http
          .getUrl(base.replace(path: '/api/history/$filename'))
          .timeout(_timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_timeout);
      if (optional &&
          (response.statusCode == 404 ||
              response.statusCode == 200 &&
                  response.headers.contentType?.mimeType == 'text/html')) {
        await response.drain<void>().timeout(_timeout);
        return null;
      }
      if (response.statusCode != 200) {
        await response.drain<void>().timeout(_timeout);
        throw GaggimateException(
          GaggimateFailure.unavailable,
          reason: '$filename: HTTP ${response.statusCode}',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        bytes.add(chunk);
        if (bytes.length > _maxBytes) {
          throw const GaggimateException(GaggimateFailure.invalidData);
        }
      }
      final result = bytes.takeBytes();
      if (optional) {
        final prefix = utf8
            .decode(result.take(256).toList(), allowMalformed: true)
            .trimLeft()
            .toLowerCase();
        if (prefix.startsWith('<!doctype html') || prefix.startsWith('<html')) {
          return null;
        }
      }
      return result;
    } on GaggimateException {
      rethrow;
    } on Object {
      throw const GaggimateException(GaggimateFailure.connection);
    }
  }

  @override
  Future<List<GaggimateHistoryEntry>> history() async {
    final bytes = await _get('index.bin');
    try {
      return decodeGaggimateIndex(bytes!);
    } on FormatException catch (error) {
      throw GaggimateException(
        GaggimateFailure.invalidData,
        reason: 'index.bin: ${error.message}',
      );
    }
  }

  @override
  Future<GaggimateShot> shot(GaggimateHistoryEntry entry) async {
    if (!RegExp(r'^\d{1,10}$').hasMatch(entry.id)) {
      throw const GaggimateException(GaggimateFailure.invalidData);
    }
    final name = entry.id.padLeft(6, '0');
    final bytes = await _get('$name.slog');
    var noteBytes = await _get('$name.json', optional: true);
    if (noteBytes == null && name != entry.id) {
      noteBytes = await _get('${entry.id}.json', optional: true);
    }
    try {
      final Object? notes = noteBytes == null
          ? null
          : jsonDecode(utf8.decode(noteBytes));
      if (notes != null && notes is! Map<String, dynamic>) {
        throw const FormatException('Invalid shot notes');
      }
      final shot = decodeGaggimateShot(
        bytes!,
        id: entry.id,
        machineAddress: machineAddress,
        notes: notes == null
            ? const {}
            : (notes as Map<String, dynamic>).cast<String, Object?>(),
      );
      if (shot.brewedAt != entry.brewedAt) {
        throw const FormatException('History changed while reading');
      }
      return shot;
    } on FormatException catch (error) {
      throw GaggimateException(
        GaggimateFailure.invalidData,
        reason: 'shot ${entry.id}: ${error.message}',
      );
    }
  }

  @override
  void close() => _http.close(force: true);
}
