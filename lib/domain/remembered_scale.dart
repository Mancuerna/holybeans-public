import 'dart:convert';

class RememberedScale {
  const RememberedScale({required this.deviceId, required this.name});

  final String deviceId;
  final String name;

  static List<RememberedScale> decodeList(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! List) throw const FormatException('Invalid paired scales');
    final ids = <String>{};
    return [
      for (final item in decoded)
        switch (item) {
          {'id': final String id, 'name': final String name}
              when id.isNotEmpty && name.isNotEmpty && ids.add(id) =>
            RememberedScale(deviceId: id, name: name),
          _ => throw const FormatException('Invalid or duplicate paired scale'),
        },
    ];
  }
}
