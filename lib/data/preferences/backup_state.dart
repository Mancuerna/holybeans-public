import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Backup state that belongs to this phone rather than to the journal: the
/// chosen folder and what was last saved there. It lives in a small JSON
/// file next to the database, so it never travels inside a backup, survives
/// a restore and needs no schema change.
class BackupState {
  /// Reads what it can; unexpected values are dropped, never fatal.
  factory BackupState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const BackupState();
    T? read<T>(String key) => json[key] is T ? json[key] as T : null;
    final uri = read<String>('folderUri');
    return BackupState(
      journalFingerprint: read<String>('journalFingerprint'),
      journalEmpty: read<bool>('journalEmpty') ?? true,
      folderUri: uri,
      folderName: uri == null ? null : read<String>('folderName'),
      folderSavedAtMs: uri == null ? null : read<int>('folderSavedAtMs'),
      folderFingerprint: uri == null ? null : read<String>('folderFingerprint'),
      folderDismissedDay: uri == null
          ? null
          : read<String>('folderDismissedDay'),
    );
  }
  const BackupState({
    this.journalFingerprint,
    this.journalEmpty = true,
    this.folderUri,
    this.folderName,
    this.folderSavedAtMs,
    this.folderFingerprint,
    this.folderDismissedDay,
  });

  /// Fingerprint of the journal when the app last went to the background.
  final String? journalFingerprint;
  final bool journalEmpty;

  /// The folder picked for daily copies (an Android tree URI) and its name.
  final String? folderUri;
  final String? folderName;

  /// When and with which journal the last daily copy was saved there.
  final int? folderSavedAtMs;
  final String? folderFingerprint;

  /// Local day (`yyyy-mm-dd`) on which the daily reminder was put off.
  final String? folderDismissedDay;

  DateTime? get folderSavedAt => switch (folderSavedAtMs) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  };

  BackupState withJournal(String fingerprint, {required bool empty}) =>
      BackupState(
        journalFingerprint: fingerprint,
        journalEmpty: empty,
        folderUri: folderUri,
        folderName: folderName,
        folderSavedAtMs: folderSavedAtMs,
        folderFingerprint: folderFingerprint,
        folderDismissedDay: folderDismissedDay,
      );

  /// A newly chosen folder starts without copies or reminders.
  BackupState withFolder(String uri, String name) => BackupState(
    journalFingerprint: journalFingerprint,
    journalEmpty: journalEmpty,
    folderUri: uri,
    folderName: name,
  );

  BackupState withoutFolder() => BackupState(
    journalFingerprint: journalFingerprint,
    journalEmpty: journalEmpty,
  );

  BackupState withFolderCopy(DateTime at, String fingerprint) => BackupState(
    journalFingerprint: fingerprint,
    journalEmpty: journalEmpty,
    folderUri: folderUri,
    folderName: folderName,
    folderSavedAtMs: at.millisecondsSinceEpoch,
    folderFingerprint: fingerprint,
    folderDismissedDay: folderDismissedDay,
  );

  BackupState withDismissed(String day) => BackupState(
    journalFingerprint: journalFingerprint,
    journalEmpty: journalEmpty,
    folderUri: folderUri,
    folderName: folderName,
    folderSavedAtMs: folderSavedAtMs,
    folderFingerprint: folderFingerprint,
    folderDismissedDay: day,
  );

  Map<String, Object?> toJson() => {
    'journalFingerprint': journalFingerprint,
    'journalEmpty': journalEmpty,
    'folderUri': folderUri,
    'folderName': folderName,
    'folderSavedAtMs': folderSavedAtMs,
    'folderFingerprint': folderFingerprint,
    'folderDismissedDay': folderDismissedDay,
  };
}

/// Loads and saves [BackupState] atomically in one app-private file.
class BackupStateStore {
  BackupStateStore(this.file);

  final File file;
  late final _json = AtomicJsonFile(file);

  static Future<BackupStateStore> open() async {
    final support = await getApplicationSupportDirectory();
    return BackupStateStore(File(path.join(support.path, 'backup_state.json')));
  }

  /// The saved state; a missing or damaged file reads as empty.
  Future<BackupState> load() async {
    try {
      return BackupState.fromJson(await _json.read());
    } on FormatException {
      return const BackupState();
    } on FileSystemException {
      return const BackupState();
    }
  }

  Future<void> save(BackupState state) => _json.write(state.toJson());
}
