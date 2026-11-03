import 'dart:convert';

import 'package:holybeans/domain/label_printer_profile.dart';

// Bounded, in-memory connection diagnostics. Never retain bitmap rows, label
// text, advertised names, device addresses or the journal. Copy is explicit.
class NiimbotConnectionLog {
  NiimbotConnectionLog(this.model);
  final LabelPrinterModel model;
  final _lines = <String>[];
  final _clock = Stopwatch()..start();

  String get report => _lines.isEmpty
      ? ''
      : 'HolyBeans Niimbot connection report v2\n'
            'Selected: ${model.label}\n${_lines.join('\n')}';

  void record(String event, Map<String, Object?> data) {
    final selected = switch (event) {
      'status' => {'previous': data['previous'], 'next': data['next']},
      'adapter' => {'state': data['state']},
      'connection.changed' => {'linked': data['linked']},
      'niimbot.receive' => {
        'bytes': data['bytes'],
        'decoded': data['decoded'],
        'buffered': data['buffered'],
        'invalidFrames': data['invalidFrames'],
        'expected': data['expected'],
      },
      'niimbot.writeComplete' => {'command': data['command']},
      'niimbot.mtu.request' => {'requested': data['requested']},
      'niimbot.mtu.result' => {'mtu': data['mtu']},
      'niimbot.request' ||
      'niimbot.response' ||
      'niimbot.identified' ||
      'niimbot.unexpectedResponse' => data,
      'connect.error' ||
      'niimbot.mtu.error' ||
      'reconnect.error' ||
      'subscribe.error' ||
      'permissions.error' ||
      'notification.error' ||
      'disconnect.error' => {'error': _redact('${data['error']}')},
      'permissions.request' ||
      'permissions.granted' ||
      'connect.start' ||
      'connect.linked' ||
      'gatt.services' ||
      'gatt.selected' ||
      'subscribe.start' ||
      'subscribe.ok' ||
      'connection.close' => <String, Object?>{},
      _ => null,
    };
    if (selected == null) return;
    _lines.add(
      '${_clock.elapsedMilliseconds}ms $event ${jsonEncode(selected)}',
    );
    if (_lines.length > 120) _lines.removeAt(0);
  }

  String _redact(String error) {
    final safe = error
        .replaceAll(
          RegExp(r'(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'),
          '[address]',
        )
        .replaceAll(
          RegExp(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'),
          '[identifier]',
        );
    return safe.length > 512 ? safe.substring(0, 512) : safe;
  }
}
