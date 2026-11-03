import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// A shot from a Meticulous espresso machine's history, reduced to what a
/// brew in HolyBeans can hold.
class MeticulousShot {
  /// Builds a shot from one entry of `GET /api/v1/history`. With
  /// `dump_data=false` the entry has no curve and the measured fields stay
  /// null.
  factory MeticulousShot.fromHistoryEntry(Map<String, Object?> entry) {
    final profile = _map(entry['profile']);
    final time = _number(entry['time']);
    if (entry['id'] is! String || time == null) {
      throw const FormatException('History entry without id or time');
    }
    final curve = _measure(entry['data']);
    return MeticulousShot(
      id: entry['id']! as String,
      brewedAt: DateTime.fromMillisecondsSinceEpoch((time * 1000).round()),
      profileName:
          (entry['name'] as String?) ?? (profile['name'] as String?) ?? '',
      profileAuthor: profile['author'] as String?,
      temperatureC: _number(profile['temperature'])?.toDouble(),
      targetWeightGrams: _number(profile['final_weight'])?.toDouble(),
      timeSeconds: curve?.timeSeconds,
      yieldGrams: curve?.yieldGrams,
      peakPressureBar: curve?.peakPressureBar,
      preinfusionSeconds: curve?.preinfusionSeconds,
      firstDripSeconds: curve?.firstDripSeconds,
      curve: curve?.curve,
    );
  }
  const MeticulousShot({
    required this.id,
    required this.brewedAt,
    required this.profileName,
    this.profileAuthor,
    this.temperatureC,
    this.targetWeightGrams,
    this.timeSeconds,
    this.yieldGrams,
    this.peakPressureBar,
    this.preinfusionSeconds,
    this.firstDripSeconds,
    this.curve,
  });

  /// The machine's shot UUID, stable across requests.
  final String id;
  final DateTime brewedAt;
  final String profileName;
  final String? profileAuthor;

  /// Brew temperature set in the profile.
  final double? temperatureC;

  /// Weight at which the profile ends the shot.
  final double? targetWeightGrams;

  /// Measured from the shot curve; null when it was not requested.
  final int? timeSeconds;
  final double? yieldGrams;
  final double? peakPressureBar;

  /// Time spent in profile stages named pre-infusion, soak or bloom.
  final int? preinfusionSeconds;

  /// Machine elapsed time at the first extraction sample weighing at least
  /// 0.1 g, rounded to whole seconds (at least one); null without a qualifying sample.
  final int? firstDripSeconds;

  /// Pressure, flow and weight over time; null when not requested.
  final ShotCurve? curve;
}

/// Statuses that are not part of the extraction itself.
const _auxiliaryStatuses = {'retracting', 'purge', 'heating', 'idle'};
final _preinfusionStage = RegExp(
  r'pre.?infus|soak|bloom|remojo',
  caseSensitive: false,
);

({
  int? timeSeconds,
  double? yieldGrams,
  double? peakPressureBar,
  int? preinfusionSeconds,
  int? firstDripSeconds,
  ShotCurve? curve,
})?
_measure(Object? data) {
  if (data is! List || data.isEmpty) return null;
  final samples = [
    for (final sample in data)
      if (sample is Map) _map(sample),
  ];
  num? timeOf(Map<String, Object?> sample) => _number(sample['time']);
  Map<String, Object?> shotOf(Map<String, Object?> sample) =>
      _map(sample['shot']);
  String statusOf(Map<String, Object?> sample) =>
      (sample['status'] as String? ?? '').trim();

  final extraction = [
    for (final sample in samples)
      if (!_auxiliaryStatuses.contains(statusOf(sample).toLowerCase())) sample,
  ];
  int? timeSeconds;
  double? peak;
  int? preinfusion;
  int? firstDrip;
  if (extraction.isNotEmpty) {
    final start = timeOf(extraction.first) ?? 0;
    // The shot ends where the extraction stages stop, usually when the
    // piston starts retracting.
    final endSample = samples.firstWhere(
      (sample) =>
          statusOf(sample).toLowerCase() == 'retracting' &&
          (timeOf(sample) ?? 0) >= start,
      orElse: () => extraction.last,
    );
    final end = timeOf(endSample) ?? start;
    timeSeconds = ((end - start) / 1000).round();
    for (final sample in extraction) {
      final shot = shotOf(sample);
      final weight = _number(shot['weight']);
      final time = timeOf(sample);
      if (firstDrip == null &&
          weight != null &&
          weight >= 0.1 &&
          time != null &&
          time >= 0) {
        firstDrip = math.max(1, (time / 1000).round());
      }
      final pressure = _number(shot['pressure'])?.toDouble();
      if (pressure != null && (peak == null || pressure > peak)) {
        peak = pressure;
      }
    }
    var preinfusionMs = 0.0;
    for (var index = 0; index < extraction.length - 1; index++) {
      if (!_preinfusionStage.hasMatch(statusOf(extraction[index]))) continue;
      final from = timeOf(extraction[index]);
      final to = timeOf(extraction[index + 1]);
      if (from != null && to != null && to > from) preinfusionMs += to - from;
    }
    if (preinfusionMs > 0) preinfusion = (preinfusionMs / 1000).round();
  }
  // What ends up in the cup: the last weight the scale reported.
  double? yieldGrams;
  for (final sample in samples.reversed) {
    final weight = _number(shotOf(sample)['weight'])?.toDouble();
    if (weight != null) {
      yieldGrams = weight > 0 ? weight : null;
      break;
    }
  }
  // The curve starts with the extraction and keeps the retraction, while
  // the last drops still reach the cup.
  final start = extraction.isEmpty ? 0 : (timeOf(extraction.first) ?? 0);
  final times = <int>[];
  final pressures = <double>[];
  final flows = <double>[];
  final weights = <double>[];
  for (final sample in samples) {
    final time = timeOf(sample);
    if (time == null || time < start) continue;
    final shot = shotOf(sample);
    times.add((time - start).round());
    pressures.add(math.max(0, _number(shot['pressure'])?.toDouble() ?? 0));
    flows.add(math.max(0, _number(shot['flow'])?.toDouble() ?? 0));
    weights.add(math.max(0, _number(shot['weight'])?.toDouble() ?? 0));
  }
  double? tenth(double? value) =>
      value == null ? null : (value * 10).round() / 10;
  return (
    timeSeconds: timeSeconds == null || timeSeconds <= 0 ? null : timeSeconds,
    yieldGrams: tenth(yieldGrams),
    peakPressureBar: peak == null || peak < 0 ? null : tenth(peak),
    preinfusionSeconds: preinfusion,
    firstDripSeconds: firstDrip,
    curve: times.length < 2
        ? null
        : ShotCurve(
            timesMs: times,
            pressure: pressures,
            flow: flows,
            weight: weights,
          ),
  );
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

num? _number(Object? value) => switch (value) {
  final num number when number.isFinite => number,
  final String text => num.tryParse(text),
  _ => null,
};

class MeticulousException implements Exception {
  const MeticulousException(this.message);

  final String message;

  @override
  String toString() => 'MeticulousException: $message';
}

/// Read-only access to a Meticulous machine's shot history.
abstract interface class MeticulousSource {
  /// The most recent shots, newest first; with [withCurves] they include
  /// their measurements, which makes the response much larger.
  Future<List<MeticulousShot>> recentShots({
    int limit = 50,
    bool withCurves = false,
  });

  /// One shot with the measurements taken from its curve.
  Future<MeticulousShot> shot(String id);

  /// "like", "dislike" or null, as rated on the machine.
  Future<String?> rating(String id);

  /// The latest pour over made on the machine's scale, when it was a free
  /// pour; null otherwise. Only the latest can be read from outside the
  /// machine: its pour-over list answers local requests only.
  Future<MeticulousFreePour?> lastFreePour();
}

/// Opens a source for a machine address; tests replace it with a fake.
MeticulousSource Function(String address) connectMeticulous =
    MeticulousClient.new;

/// Talks to the machine's HTTP API using only GET requests to history
/// endpoints (shots and pour overs), which read the history database and
/// files without changing anything (see docs/DATA.md). No other endpoint is
/// ever called.
class MeticulousClient implements MeticulousSource {
  MeticulousClient(String address, {HttpClient? httpClient})
    : base = normalizeAddress(address),
      _http = httpClient ?? HttpClient();

  final Uri base;
  final HttpClient _http;

  static const _timeout = Duration(seconds: 15);

  /// Accepts "192.168.1.50", "meticulous.local:8080" or a full URL.
  static Uri normalizeAddress(String address) {
    final text = address.trim();
    if (text.isEmpty) throw const FormatException('Empty address');
    final uri = Uri.parse(text.contains('://') ? text : 'http://$text');
    if (uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) {
      throw FormatException('Invalid address', address);
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
  }

  /// The JSON at [path]; with [missingIsNull], null when the machine
  /// answers 404 (nothing there, or a firmware without that history).
  Future<Object?> _get(
    String path,
    Map<String, String> query, {
    bool missingIsNull = false,
  }) async {
    final uri = base.replace(
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
    try {
      final request = await _http.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body = await utf8.decodeStream(response).timeout(_timeout);
      if (missingIsNull && response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw MeticulousException('HTTP ${response.statusCode} for $path');
      }
      return jsonDecode(body);
    } on MeticulousException {
      rethrow;
    } on FormatException catch (error) {
      throw MeticulousException('Invalid response: ${error.message}');
    } on Object catch (error) {
      throw MeticulousException('$error');
    }
  }

  List<Map<String, Object?>> _history(Object? json) {
    final history = json is Map ? json['history'] : null;
    if (history is! List) {
      throw const MeticulousException('Response without history');
    }
    return [
      for (final entry in history)
        if (entry is Map) entry.cast<String, Object?>(),
    ];
  }

  @override
  Future<List<MeticulousShot>> recentShots({
    int limit = 50,
    bool withCurves = false,
  }) async {
    final entries = _history(
      await _get('/api/v1/history', {
        'max_results': '$limit',
        'dump_data': '$withCurves',
      }),
    );
    return [for (final entry in entries) ?_tryParse(entry)];
  }

  @override
  Future<MeticulousShot> shot(String id) async {
    final entries = _history(
      await _get('/api/v1/history', {
        'ids': id,
        'max_results': '1',
        'dump_data': 'true',
      }),
    );
    final entry = entries.where((entry) => entry['id'] == id).firstOrNull;
    if (entry == null) throw MeticulousException('Shot $id not found');
    return MeticulousShot.fromHistoryEntry(entry);
  }

  @override
  Future<String?> rating(String id) async {
    final json = await _get('/api/v1/history/rating/$id', const {});
    final rating = json is Map ? json['rating'] : null;
    return rating is String ? rating : null;
  }

  @override
  Future<MeticulousFreePour?> lastFreePour() async {
    final last = await _get(
      '/api/v1/history/pour-over/last',
      const {},
      missingIsNull: true,
    );
    if (last is! Map || last['mode'] != 'free_pour') return null;
    final file = last['file'];
    if (file is! String || file.isEmpty) return null;
    final record = await _get(
      '/api/v1/history/pour-over/files/$file',
      const {},
    );
    try {
      if (record is! Map) throw const FormatException('Not a record');
      return MeticulousFreePour.fromRecord(record.cast<String, Object?>());
    } on FormatException catch (error) {
      throw MeticulousException('Invalid free pour: ${error.message}');
    }
  }

  MeticulousShot? _tryParse(Map<String, Object?> entry) {
    try {
      return MeticulousShot.fromHistoryEntry(entry);
    } on FormatException {
      return null;
    }
  }
}
