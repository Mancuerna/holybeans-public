import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Independent decoder of Gaggimate's documented SIDX/SHOT wire formats.
/// See docs/DATA.md for the pinned protocol reference and supported versions.
List<GaggimateHistoryEntry> decodeGaggimateIndex(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 32 ||
      data.getUint32(0, Endian.little) != 0x58444953 ||
      data.getUint16(4, Endian.little) != 1 ||
      data.getUint16(6, Endian.little) != 128) {
    throw const FormatException('Unsupported history index');
  }
  final count = data.getUint32(8, Endian.little);
  if (bytes.length != 32 + count * 128) {
    throw const FormatException('Incomplete history index');
  }
  final result = <GaggimateHistoryEntry>[];
  for (var i = 0; i < count; i++) {
    final offset = 32 + i * 128;
    final flags = data.getUint8(offset + 15);
    if (flags & 2 != 0 || flags & 1 == 0) continue;
    result.add(
      GaggimateHistoryEntry(
        id: '${data.getUint32(offset, Endian.little)}',
        brewedAt: DateTime.fromMillisecondsSinceEpoch(
          data.getUint32(offset + 4, Endian.little) * 1000,
        ),
        profileName: _text(bytes, offset + 48, 48),
        durationMs: data.getUint32(offset + 8, Endian.little),
      ),
    );
  }
  result.sort((a, b) => b.brewedAt.compareTo(a.brewedAt));
  return result;
}

GaggimateShot decodeGaggimateShot(
  Uint8List bytes, {
  required String id,
  required String machineAddress,
  Map<String, Object?> notes = const {},
}) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 128 || data.getUint32(0, Endian.little) != 0x544f4853) {
    throw const FormatException('Invalid shot header');
  }
  final version = data.getUint8(4);
  final size = data.getUint8(5);
  final header = data.getUint16(6, Endian.little);
  final interval = data.getUint16(8, Endian.little);
  final mask = data.getUint32(12, Endian.little);
  final count = data.getUint32(16, Endian.little);
  final duration = data.getUint32(20, Endian.little);
  final legacyV6 = version == 6 && size == 26 && mask == 0x1fff;
  final elapsed = version >= 6 && !legacyV6;
  final bits = [
    for (var bit = 0; bit < 32; bit++)
      if (mask & (1 << bit) != 0) bit,
  ];
  if (version < 1 ||
      version > 8 ||
      header != (version < 5 ? 128 : 512) ||
      bytes.length < header ||
      mask & 1 == 0 ||
      size != bits.length * 2 + (elapsed ? 2 : 0) ||
      interval == 0) {
    throw const FormatException('Unsupported shot format');
  }
  if (count == 0 || count > 100000 || bytes.length != header + count * size) {
    throw const FormatException('Incomplete shot recording');
  }
  final samples = <Map<int, int>>[];
  for (var i = 0; i < count; i++) {
    var offset = header + i * size;
    final sample = <int, int>{};
    for (final bit in bits) {
      final wide = elapsed && bit == 0;
      sample[bit] = wide
          ? data.getUint32(offset, Endian.little)
          : bit >= 5 && bit <= 8
          ? data.getInt16(offset, Endian.little)
          : data.getUint16(offset, Endian.little);
      offset += wide ? 4 : 2;
    }
    if (!elapsed) sample[0] = sample[0]! * interval;
    if (i > 0 && sample[0]! <= samples.last[0]!) {
      throw const FormatException('Unordered shot samples');
    }
    samples.add(sample);
  }
  return _measure(
    bytes,
    data,
    samples,
    version,
    legacyV6,
    duration,
    id,
    machineAddress,
    notes,
  );
}

GaggimateShot _measure(
  Uint8List bytes,
  ByteData data,
  List<Map<int, int>> samples,
  int version,
  bool legacyV6,
  int duration,
  String id,
  String address,
  Map<String, Object?> notes,
) {
  bool weighed(Map<int, int> s) {
    final flags = s[12];
    return flags != null &&
        flags & ((version >= 8 || legacyV6) ? 0x100 : 4) != 0;
  }

  // The recording can continue after the pump stops to collect the last drips.
  final extended = samples.where((s) => (s[12] ?? 0) & 16 != 0).firstOrNull;
  final end = extended?[0] ?? duration;
  if (end <= 0) throw const FormatException('Invalid shot duration');
  final extraction = samples.where((s) => s[0]! < end).toList();
  final pressure = extraction
      .where((s) => s.containsKey(4))
      .map((s) => s[4]! / 10);
  final lastSample = samples.last;
  final last = weighed(lastSample) && lastSample.containsKey(9)
      ? lastSample
      : null;
  // Omit whole scale series on a gap: never draw a fabricated zero or estimate.
  final continuousWeight = samples.every((s) => weighed(s) && s.containsKey(9));
  final continuousFlow =
      continuousWeight && samples.every((s) => s.containsKey(8));
  final peak = pressure.isEmpty ? null : pressure.reduce(math.max);
  final firstDrip = extraction
      .where((s) => weighed(s) && (s[9] ?? 0) >= 1)
      .firstOrNull;
  if (version >= 5) {
    final phases = data.getUint8(458);
    if (phases > 12) throw const FormatException('Invalid phase count');
    for (var i = 0; i < phases; i++) {
      final offset = 110 + 29 * i;
      final startIndex = data.getUint16(offset, Endian.little);
      final stopIndex = i + 1 < phases
          ? data.getUint16(offset + 29, Endian.little)
          : samples.length;
      if (startIndex >= samples.length ||
          stopIndex > samples.length ||
          stopIndex < startIndex) {
        throw const FormatException('Invalid phase samples');
      }
    }
  }
  final target = extraction.map((s) => s[1]).whereType<int>().firstOrNull;
  final hasPressure = samples.every((s) => s.containsKey(4));
  final curve = samples.length < 2 || (!continuousWeight && !hasPressure)
      ? null
      : ShotCurve(
          timesMs: samples.map((s) => s[0]!).toList(),
          pressure: hasPressure
              ? samples.map((s) => s[4]! / 10).toList()
              : const [],
          flow: continuousFlow
              ? samples.map((s) => s[8]! / 100).toList()
              : const [],
          weight: continuousWeight
              ? samples.map((s) => s[9]! / 10).toList()
              : const [],
        );
  // Header weight is a maximum and may include a cup being replaced. Prefer
  // the final healthy scale sample. Estimates (ev) are deliberately not used.
  return GaggimateShot(
    id: id,
    machineAddress: address,
    brewedAt: DateTime.fromMillisecondsSinceEpoch(
      data.getUint32(24, Endian.little) * 1000,
    ),
    profileName: _text(bytes, 60, 48),
    timeSeconds: math.max(1, (end / 1000).round()),
    yieldGrams: last == null || last[9]! == 0 ? null : last[9]! / 10,
    temperatureC: target == null || target <= 0 || target > 1500
        ? null
        : target / 10,
    peakPressureBar: peak == null || peak > 30 ? null : peak,
    firstDripSeconds: firstDrip == null
        ? null
        : math.max(1, (firstDrip[0]! / 1000).round()),
    // Phase names and delayed first drips do not establish intentional preinfusion.
    // Leave it unset for the user to enter from their knowledge of the profile.
    doseGrams: _positive(notes['doseIn']),
    grindSetting: _optionalText(notes['grindSetting']),
    notes: _optionalText(notes['notes']),
    curve: curve,
  );
}

String _text(Uint8List bytes, int start, int length) => utf8.decode(
  bytes.sublist(start, start + length).takeWhile((b) => b != 0).toList(),
);
String? _optionalText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
double? _positive(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite && number > 0 && number <= 1000
      ? number
      : null;
}
