import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/auto_backup.dart';

String _source({
  List<Object> coffees = const [],
  List<Object> brews = const [],
  int? lastBackupAtMs,
  String exportedAt = '2026-10-04T10:00:00.000Z',
}) => jsonEncode({
  'format': 'holybeans-backup',
  'version': 21,
  'exportedAt': exportedAt,
  'data': {
    'coffees': coffees,
    'brews': brews,
    'preferences': [
      {'id': 1, 'localeCode': 'es', 'lastBackupAtMs': lastBackupAtMs},
    ],
  },
});

AutoBackupEntry _entry(DateTime at, String fingerprint) =>
    AutoBackupEntry.parse(AutoBackupEntry.nameFor(at, fingerprint))!;

void main() {
  test(
    'recognizes verified daily versions and keeps manual or partial files out',
    () {
      final version = 'holybeans-backup-2026-10-18-${'a' * 32}.zip';
      expect(
        folderBackupNames([
          version,
          'holybeans-backup-2026-10-17.zip',
          '.holybeans-partial-abc',
          'holybeans-backup-v31.zip',
        ]),
        [version, 'holybeans-backup-2026-10-17.zip'],
      );
    },
  );

  const fingerprint = '0123456789abcdef';

  test('automatic copy names keep their time and fingerprint', () {
    final at = DateTime.utc(2026, 10, 4, 18, 30, 5);
    final name = AutoBackupEntry.nameFor(at, fingerprint);
    expect(name, 'holybeans-auto-20261004T183005Z-0123456789abcdef.zip');
    final entry = AutoBackupEntry.parse(name)!;
    expect(entry.savedAt, at);
    expect(entry.fingerprint, fingerprint);
    for (final other in [
      'holybeans-backup-2026-10-04.zip',
      '.$name.tmp',
      'holybeans-auto-20261304T183005Z-0123456789abcdef.zip',
      'holybeans-auto-20261004T183005Z-0123.zip',
    ]) {
      expect(AutoBackupEntry.parse(other), isNull, reason: other);
    }
  });

  test('entries are listed newest first, ignoring other files', () {
    final older = AutoBackupEntry.nameFor(DateTime.utc(2026, 10), 'a' * 16);
    final newer = AutoBackupEntry.nameFor(DateTime.utc(2026, 10, 3), 'b' * 16);
    expect(
      autoBackupEntries([older, 'notes.txt', newer])
          .map((entry) => entry.fileName),
      [newer, older],
    );
  });

  group('a new automatic copy', () {
    final now = DateTime.utc(2026, 10, 4, 12);

    test('is never made of an empty journal', () {
      expect(
        autoBackupNeeded(
          entries: const [],
          fingerprint: fingerprint,
          journalEmpty: true,
          now: now,
          force: true,
        ),
        isFalse,
      );
    });

    test('is made first, then once a day and only after changes', () {
      bool needed(
        List<AutoBackupEntry> entries,
        String print, {
        bool force = false,
      }) => autoBackupNeeded(
        entries: entries,
        fingerprint: print,
        journalEmpty: false,
        now: now,
        force: force,
      );
      expect(needed(const [], fingerprint), isTrue);
      final hourAgo = [
        _entry(now.subtract(const Duration(hours: 1)), 'a' * 16),
      ];
      expect(needed(hourAgo, fingerprint), isFalse);
      expect(needed(hourAgo, fingerprint, force: true), isTrue);
      expect(needed(hourAgo, 'a' * 16, force: true), isFalse);
      final dayAgo = [
        _entry(now.subtract(const Duration(hours: 24)), 'a' * 16),
      ];
      expect(needed(dayAgo, fingerprint), isTrue);
      expect(needed(dayAgo, 'a' * 16), isFalse);
      // A copy dated in the future means the clock moved back.
      final future = [_entry(now.add(const Duration(hours: 3)), 'a' * 16)];
      expect(needed(future, fingerprint), isTrue);
    });
  });

  test('only copies beyond the newest ones are stale', () {
    expect(staleBackups(['c', 'b', 'a'], 3), isEmpty);
    expect(staleBackups(['d', 'c', 'b', 'a'], 2), ['b', 'a']);
  });

  test('daily folder copies use the local day and touch only their files', () {
    final evening = DateTime(2026, 10, 4, 23, 50);
    expect(folderBackupName(evening), 'holybeans-backup-2026-10-04.zip');
    expect(
      folderBackupNames([
        'holybeans-backup-2026-10-03.zip',
        'holybeans-backup-v21.zip',
        'holybeans-backup-2026-10-04.zip',
        'holybeans-backup-2026-10-04 (1).zip',
        'photo.jpg',
      ]),
      ['holybeans-backup-2026-10-04.zip', 'holybeans-backup-2026-10-03.zip'],
    );
  });

  test('the daily reminder needs changes and is shown once a day', () {
    final now = DateTime(2026, 10, 4, 9);
    bool due({
      String? journal = 'b',
      bool empty = false,
      String? folder = 'a',
      String? savedDay = '2026-10-03',
      String? dismissedDay,
    }) => folderBackupDue(
      journalFingerprint: journal,
      journalEmpty: empty,
      lastFolderFingerprint: folder,
      lastFolderDay: savedDay,
      dismissedDay: dismissedDay,
      now: now,
    );
    expect(due(), isTrue);
    expect(due(folder: null, savedDay: null), isTrue);
    expect(due(journal: null), isFalse);
    expect(due(empty: true), isFalse);
    expect(due(folder: 'b'), isFalse);
    expect(due(savedDay: '2026-10-04'), isFalse);
    expect(due(dismissedDay: '2026-10-04'), isFalse);
    expect(due(dismissedDay: '2026-10-03'), isTrue);
  });

  test('fingerprints are 16 hex digits, even for negative hashes', () {
    expect(fingerprintHex(0), '0000000000000000');
    expect(fingerprintHex(-1), 'ffffffffffffffff');
    expect(fingerprintHex(-0x18c4659be3985f98), 'e73b9a641c67a068');
    expect(fingerprintHex(0x0123456789abcdef), '0123456789abcdef');
  });

  test('the fingerprint follows the journal, not export times', () {
    final coffee = {'id': 'c1', 'name': 'Coffee'};
    final base = journalDigest(_source(coffees: [coffee]));
    expect(base.fingerprint, hasLength(16));
    expect(base.empty, isFalse);
    expect(
      journalDigest(
        _source(
          coffees: [coffee],
          lastBackupAtMs: 99,
          exportedAt: '2026-10-05T00:00:00.000Z',
        ),
      ).fingerprint,
      base.fingerprint,
    );
    expect(
      journalDigest(
        _source(
          coffees: [
            {'id': 'c1', 'name': 'Coffee!'},
          ],
        ),
      ).fingerprint,
      isNot(base.fingerprint),
    );
    expect(journalDigest(_source()).empty, isTrue);
    expect(
      journalDigest(
        _source(
          brews: [
            {'id': 'b1'},
          ],
        ),
      ).empty,
      isFalse,
    );
  });
}
