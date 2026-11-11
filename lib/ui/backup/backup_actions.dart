import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/brew_csv.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';
import 'package:share_plus/share_plus.dart';

/// Saving, sharing and restoring the journal: the ZIP backup, the CSV of
/// brews and a restore that asks first. A backup handed to another app is
/// remembered, so the app can tell when the next one is due. Every restore
/// first keeps the current journal among the automatic copies.
class BackupActions {
  BackupActions({
    required this.center,
    required this.repository,
    required this.photos,
    required this.message,
  });

  final BackupCenter center;
  final JournalRepository repository;
  final PhotoStore? photos;

  JournalBackup get backup => center.backup;

  /// Shows a short notice to the user.
  final void Function(String text) message;

  Future<void> exportBackup(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      // A ZIP carries the journal and its photos together.
      final bytes = await backup.exportArchive(photos);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/zip')],
          fileNameOverrides: ['holybeans-backup-v${JournalBackup.version}.zip'],
        ),
      );
      if (result.status != ShareResultStatus.dismissed) {
        await center.settings.markBackedUp(DateTime.now());
      }
    } catch (error, stack) {
      reportError(error, stack);
      message(s.backupFailed);
    }
  }

  /// Saves today's copy to the chosen folder.
  Future<void> saveToFolder(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      await center.saveToFolder();
      message(s.backupFolderSaved(center.state.folderName ?? ''));
    } catch (error, stack) {
      reportError(error, stack);
      message(s.backupFolderFailed);
    }
  }

  /// Picks the folder for daily copies and saves the first one there.
  Future<void> chooseFolder(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      if (await center.chooseFolder()) {
        message(s.backupFolderSaved(center.state.folderName ?? ''));
      }
    } catch (error, stack) {
      reportError(error, stack);
      message(s.backupFolderFailed);
    }
  }

  /// Shares every brew as a CSV file for spreadsheets.
  Future<void> exportBrewsCsv(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      final csv = brewsCsv(
        brews: await repository.allBrews(),
        coffees: await repository.allCoffees(),
        lots: await repository.allLots(),
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv')],
          fileNameOverrides: ['holybeans-brews-$today.csv'],
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      message(s.backupFailed);
    }
  }

  /// Replaces the journal with a backup the user picks, after confirming.
  Future<void> importBackup(
    BuildContext context, {
    Future<XFile?> Function()? pickFile,
  }) async {
    final s = AppLocalizations.of(context);
    try {
      const backupTypes = XTypeGroup(
        label: 'HolyBeans',
        extensions: ['zip', 'json'],
      );
      final file =
          await (pickFile?.call() ??
              openFile(acceptedTypeGroups: [backupTypes]));
      if (file == null || !context.mounted) return;
      if (await file.length() > 500 * 1024 * 1024) {
        message(s.fileTooLarge);
        return;
      }
      final contents = await JournalBackup.readInBackground(
        await file.readAsBytes(),
      );
      if (!context.mounted ||
          !await _confirmRestore(context, contents.summary)) {
        return;
      }
      await _keepCurrentJournal();
      await backup.restoreWithPhotos(contents.source, contents.photos, photos);
      message(s.restored);
    } on FormatException {
      message(s.invalidBackup);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.restoreFailed);
    }
  }

  /// Replaces the journal with one of the automatic copies, after
  /// confirming. Those copies hold no photos: the photos still on the phone
  /// are kept and linked again.
  Future<void> restoreAutoBackup(
    BuildContext context,
    AutoBackupEntry entry,
  ) async {
    final s = AppLocalizations.of(context);
    final services = center.services;
    if (services == null) return;
    try {
      final contents = await JournalBackup.readInBackground(
        await services.autoBackups.read(entry),
        archiveOnly: true,
      );
      if (!context.mounted ||
          !await _confirmRestore(context, contents.summary)) {
        return;
      }
      await _keepCurrentJournal();
      await backup.restoreJson(
        contents.source,
        availablePhotos: await photos?.names() ?? const {},
      );
      message(s.restored);
    } on FormatException {
      message(s.invalidBackup);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.restoreFailed);
    }
  }

  /// Replaces the journal with the one kept before an update changed its
  /// schema, brought up to date, after confirming. Like the automatic
  /// copies, it holds no photos: those on the phone are linked again.
  Future<void> restorePreMigration(
    BuildContext context,
    PreMigrationCopy copy,
  ) async {
    final s = AppLocalizations.of(context);
    final copies = center.services?.preMigration;
    if (copies == null) return;
    try {
      final source = await copies.exportJson(copy);
      final summary = await JournalBackup.inspectJsonInBackground(source);
      if (!context.mounted || !await _confirmRestore(context, summary)) {
        return;
      }
      await _keepCurrentJournal();
      await backup.restoreJson(
        source,
        availablePhotos: await photos?.names() ?? const {},
      );
      message(s.restored);
    } on FormatException {
      message(s.invalidBackup);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.restoreFailed);
    }
  }

  Future<bool> _confirmRestore(
    BuildContext context,
    BackupSummary summary,
  ) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.restoreTitle),
        content: Text(
          [
            s.restoreWarning(summary.coffees, summary.brews),
            if (summary.cafeDrinks > 0)
              '${s.cafeDrinksLabel}: ${summary.cafeDrinks}',
            if (summary.cuppingSessions > 0)
              s.cuppingBackup(summary.cuppingSessions),
            if (center.hasAutoBackups) s.restoreKeepsCurrent,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.restore),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// A copy of the journal about to be replaced. Failing to save it must not
  /// block a restore, which may be the way out of a damaged journal.
  Future<void> _keepCurrentJournal() async {
    try {
      await center.beforeRestore();
    } catch (error, stack) {
      reportError(error, stack);
    }
  }
}
