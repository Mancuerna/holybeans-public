import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/backup_reminder.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_center.dart';

/// The backup reminder Home shows, if any: today's copy to the chosen
/// folder, a folder that can no longer be reached, or the monthly reminder
/// when there is no folder. Includes its own space below.
class BackupReminders extends StatelessWidget {
  const BackupReminders({
    super.key,
    required this.center,
    required this.coffees,
    required this.brews,
    required this.onExport,
    required this.onSaveToFolder,
    required this.onChooseFolder,
  });

  final BackupCenter center;
  final List<Coffee> coffees;
  final List<Brew> brews;
  final VoidCallback onExport;
  final VoidCallback onSaveToFolder;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: center,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final Widget? card;
      if (center.folderLost) {
        card = _ReminderCard(
          key: const ValueKey('folder-backup-lost'),
          icon: Icons.folder_off_outlined,
          title: s.folderReminderLostTitle,
          body: s.folderReminderLostBody,
          onLater: center.dismissFolderReminder,
          action: s.chooseFolder,
          actionKey: const ValueKey('folder-backup-choose'),
          onAction: onChooseFolder,
        );
      } else if (center.folderReminderDue) {
        // Daily and routine: one row, so it does not push the next brew
        // down every day the journal changes.
        card = _CompactReminder(
          key: const ValueKey('folder-backup-reminder'),
          icon: Icons.save_alt_rounded,
          title: s.folderReminderTitle,
          detail: center.state.folderName,
          semanticBody: s.folderReminderBody(center.state.folderName ?? ''),
          onLater: center.dismissFolderReminder,
          action: s.saveCopy,
          actionKey: const ValueKey('folder-backup-save'),
          onAction: onSaveToFolder,
        );
      } else if (center.monthlyReminderOpen &&
          backupDue(
            lastBackup: center.lastBackup,
            firstUse: journalFirstUse(coffees, brews),
            now: DateTime.now(),
          )) {
        final last = center.lastBackup;
        card = _ReminderCard(
          key: const ValueKey('backup-reminder'),
          icon: Icons.cloud_upload_outlined,
          title: last == null
              ? s.backupReminderNever
              : s.backupReminderDays(DateTime.now().difference(last).inDays),
          body: s.backupReminderHint,
          onLater: center.dismissMonthlyReminder,
          action: s.backupNow,
          actionKey: const ValueKey('backup-now'),
          onAction: onExport,
        );
      } else {
        card = null;
      }
      if (card == null) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(bottom: 16), child: card);
    },
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onLater,
    required this.action,
    required this.actionKey,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onLater;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(body),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(onPressed: onLater, child: Text(s.notNow)),
                  FilledButton(
                    key: actionKey,
                    onPressed: onAction,
                    child: Text(action),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A routine reminder as a single row: what to do, where, and its two
/// answers. The full sentence stays available to screen readers.
class _CompactReminder extends StatelessWidget {
  const _CompactReminder({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.semanticBody,
    required this.onLater,
    required this.action,
    required this.actionKey,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String semanticBody;
  final VoidCallback onLater;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: '$title. $semanticBody',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (detail case final folder? when folder.isNotEmpty)
                      Text(
                        folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: s.notNow,
              onPressed: onLater,
              icon: const Icon(Icons.close_rounded),
            ),
            FilledButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
