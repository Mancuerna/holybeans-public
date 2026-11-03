import 'dart:convert';

/// How many automatic copies stay inside the app, newest first.
const autoBackupsKept = 7;

/// How many daily copies stay in the folder the user chose, newest first.
const folderBackupsKept = 14;

/// Minimum time between two automatic copies inside the app.
const autoBackupInterval = Duration(hours: 24);

/// One automatic copy inside the app, described by its file name:
/// `holybeans-auto-20261004T183000Z-<fingerprint>.zip`.
class AutoBackupEntry {
  const AutoBackupEntry({
    required this.fileName,
    required this.savedAt,
    required this.fingerprint,
  });

  final String fileName;

  /// When the copy was written, in UTC.
  final DateTime savedAt;

  /// Fingerprint ([journalDigest]) of the journal the copy holds.
  final String fingerprint;

  static final _name = RegExp(
    r'^holybeans-auto-(\d{8})T(\d{6})Z-([0-9a-f]{16})\.zip$',
  );

  static String nameFor(DateTime savedAt, String fingerprint) {
    final utc = savedAt.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${utc.year.toString().padLeft(4, '0')}'
        '${two(utc.month)}${two(utc.day)}';
    final time = '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
    return 'holybeans-auto-${date}T${time}Z-$fingerprint.zip';
  }

  /// The entry a file name describes, or null for any other file.
  static AutoBackupEntry? parse(String fileName) {
    final match = _name.firstMatch(fileName);
    if (match == null) return null;
    final date = match.group(1)!;
    final time = match.group(2)!;
    final savedAt = DateTime.tryParse(
      '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6)}'
      'T${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4)}Z',
    );
    // Out-of-range parts (month 13) would roll over; reject them.
    if (savedAt == null || nameFor(savedAt, match.group(3)!) != fileName) {
      return null;
    }
    return AutoBackupEntry(
      fileName: fileName,
      savedAt: savedAt,
      fingerprint: match.group(3)!,
    );
  }
}

/// The automatic copies among [fileNames], newest first.
List<AutoBackupEntry> autoBackupEntries(Iterable<String> fileNames) =>
    [for (final name in fileNames) ?AutoBackupEntry.parse(name)]
      ..sort((a, b) => b.fileName.compareTo(a.fileName));

/// Whether to write a new automatic copy of a journal with [fingerprint].
/// Never for an empty journal, never twice for the same content, and at most
/// once per [autoBackupInterval] unless [force]d (before a restore).
bool autoBackupNeeded({
  required List<AutoBackupEntry> entries,
  required String fingerprint,
  required bool journalEmpty,
  required DateTime now,
  bool force = false,
}) {
  if (journalEmpty) return false;
  if (entries.isEmpty) return true;
  final latest = entries.first;
  if (latest.fingerprint == fingerprint) return false;
  if (force) return true;
  final since = now.toUtc().difference(latest.savedAt);
  // A copy dated in the future means the clock changed: do not wait for it.
  return since.isNegative || since >= autoBackupInterval;
}

/// Older copies beyond the newest [keep], to delete after a new one.
List<String> staleBackups(List<String> newestFirst, int keep) =>
    newestFirst.length <= keep ? const [] : newestFirst.sublist(keep);

/// The daily copy base name. Android publishes a uniquely named verified
/// version before retiring earlier copies of the same local day.
String folderBackupName(DateTime day) {
  final local = day.toLocal();
  return 'holybeans-backup-${localDay(local)}.zip';
}

final _folderName = RegExp(
  r'^holybeans-backup-\d{4}-\d{2}-\d{2}(?:-[0-9a-f]{32})?\.zip$',
);

/// The daily copies among the files of the chosen folder, newest first.
/// Any other file there, including manual backups, is never touched.
List<String> folderBackupNames(Iterable<String> fileNames) => [
  for (final name in fileNames)
    if (_folderName.hasMatch(name)) name,
]..sort((a, b) => b.compareTo(a));

/// `yyyy-mm-dd` of [time] in local time.
String localDay(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}';
}

/// Whether Home should offer today's copy to the chosen folder: the journal
/// changed since the last one, and today it has been neither saved nor put
/// off. Unknown content (not yet fingerprinted) offers nothing.
bool folderBackupDue({
  required String? journalFingerprint,
  required bool journalEmpty,
  required String? lastFolderFingerprint,
  required String? lastFolderDay,
  required String? dismissedDay,
  required DateTime now,
}) {
  if (journalFingerprint == null || journalEmpty) return false;
  if (journalFingerprint == lastFolderFingerprint) return false;
  final today = localDay(now);
  return lastFolderDay != today && dismissedDay != today;
}

/// A short, stable `fingerprint` of a backup's journal, and whether it is
/// `empty` (neither coffees nor brews). The fingerprint ignores when the
/// backup was exported and when the last backup was made, so two exports of
/// the same journal match.
({String fingerprint, bool empty}) journalDigest(String backupSource) {
  final decoded = jsonDecode(backupSource) as Map<String, dynamic>;
  final data = decoded['data'] as Map<String, dynamic>;
  final preferences = data['preferences'];
  if (preferences is List) {
    for (final row in preferences) {
      if (row is Map<String, dynamic>) row['lastBackupAtMs'] = null;
    }
  }
  final coffees = data['coffees'];
  final brews = data['brews'];
  return (
    fingerprint: _fnv1a64(utf8.encode(jsonEncode(data))),
    empty:
        (coffees is! List || coffees.isEmpty) &&
        (brews is! List || brews.isEmpty),
  );
}

String _fnv1a64(List<int> bytes) {
  // 64-bit FNV-1a; native ints wrap on overflow, as the algorithm expects.
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  return fingerprintHex(hash);
}

/// 16 lowercase hex digits of a 64-bit [value], negative ones included
/// (a native int has no unsigned 64-bit form).
String fingerprintHex(int value) {
  String half(int bits) =>
      (bits & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '${half(value >> 32)}${half(value)}';
}
