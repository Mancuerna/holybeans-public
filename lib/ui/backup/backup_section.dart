import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_actions.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Date and time of a copy in the device's regional format, like every other
/// date in the journal, e.g. "04/10/2026 18:30".
String formatBackupTime(BuildContext context, DateTime time) =>
    formatRegionalDateTime(time.toLocal(), regionalLocale);

/// Settings entries for the automatic copies and the daily copy folder.
/// Hidden where the phone services are missing (tests, other platforms).
class BackupSection extends StatelessWidget {
  const BackupSection({
    super.key,
    required this.center,
    required this.actions,
    required this.onSaveToFolder,
    required this.onChooseFolder,
  });

  final BackupCenter center;
  final BackupActions actions;
  final VoidCallback onSaveToFolder;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: center,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      if (!center.hasAutoBackups) return const SizedBox.shrink();
      final latest = center.autoEntries.firstOrNull;
      final folderName = center.state.folderName ?? '';
      return Column(
        children: [
          ListTile(
            key: const ValueKey('auto-backups'),
            leading: const Icon(Icons.history_rounded),
            title: Text(s.autoBackups),
            subtitle: Text(
              latest == null
                  ? s.autoBackupsNone
                  : s.autoBackupsLast(
                      formatBackupTime(context, latest.savedAt),
                    ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AutoBackupsPage(center: center, actions: actions),
              ),
            ),
          ),
          if (center.canUseFolder)
            ListTile(
              key: const ValueKey('backup-folder'),
              leading: Icon(
                center.hasFolder && center.folderAvailable == false
                    ? Icons.folder_off_outlined
                    : Icons.folder_outlined,
              ),
              title: Text(s.backupFolder),
              subtitle: Text(switch (center) {
                BackupCenter(hasFolder: false) => s.backupFolderNone,
                BackupCenter(folderAvailable: false) => s.backupFolderLost,
                _ => switch (center.state.folderSavedAt) {
                  final at? => s.backupFolderLast(
                    folderName,
                    formatBackupTime(context, at),
                  ),
                  null => s.backupFolderNoCopy(folderName),
                },
              }),
              isThreeLine: !center.hasFolder,
              trailing: center.savingToFolder
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: center.savingToFolder
                  ? null
                  : center.hasFolder && center.folderAvailable != false
                  ? () => _folderOptions(context)
                  : onChooseFolder,
            ),
        ],
      );
    },
  );

  Future<void> _folderOptions(BuildContext context) async {
    final s = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(s.backupFolderKept(folderBackupsKept)),
            ),
            ListTile(
              key: const ValueKey('backup-folder-save'),
              leading: const Icon(Icons.save_alt_rounded),
              title: Text(s.backupFolderSaveNow),
              onTap: () => Navigator.pop(sheetContext, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(s.backupFolderChange),
              onTap: () => Navigator.pop(sheetContext, 'change'),
            ),
            ListTile(
              key: const ValueKey('backup-folder-forget'),
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(s.backupFolderForget),
              subtitle: Text(s.backupFolderForgetHint),
              onTap: () => Navigator.pop(sheetContext, 'forget'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'save':
        onSaveToFolder();
      case 'change':
        onChooseFolder();
      case 'forget':
        try {
          await center.forgetFolder();
        } catch (error, stack) {
          reportError(error, stack);
          if (context.mounted) showOperationError(context, error, s.saveFailed);
        }
    }
  }
}

/// The automatic copies inside the app, newest first; tapping one offers to
/// restore it.
class AutoBackupsPage extends StatelessWidget {
  const AutoBackupsPage({
    super.key,
    required this.center,
    required this.actions,
  });

  final BackupCenter center;
  final BackupActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.autoBackupsTitle)),
      body: ListenableBuilder(
        listenable: center,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(s.autoBackupsExplain(autoBackupsKept)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                s.autoBackupsLimits,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (center.autoEntries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.autoBackupsEmpty),
              ),
            for (final (index, entry) in center.autoEntries.indexed)
              ListTile(
                key: ValueKey('auto-backup-$index'),
                leading: const Icon(Icons.restore_rounded),
                title: Text(formatBackupTime(context, entry.savedAt)),
                subtitle: index == 0 ? Text(s.autoBackupLatest) : null,
                onTap: () => actions.restoreAutoBackup(context, entry),
              ),
            if (center.preMigrationEntries.isNotEmpty) ...[
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  s.preMigrationTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  s.preMigrationExplain(preMigrationCopiesKept),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final (index, copy) in center.preMigrationEntries.indexed)
                ListTile(
                  key: ValueKey('pre-migration-$index'),
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: Text(formatBackupTime(context, copy.savedAt)),
                  onTap: () => actions.restorePreMigration(context, copy),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
