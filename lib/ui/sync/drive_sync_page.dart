import 'package:flutter/material.dart';
import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';

String driveStatusLabel(AppLocalizations s, DriveSyncModel model) {
  if (model.restoring) return s.driveBackupRestoring;
  if (!model.enabled) {
    return model.status == DriveSyncStatus.unavailable
        ? s.driveSyncConnectFailed
        : s.driveSyncDisabled;
  }
  return switch (model.status) {
    DriveSyncStatus.checking => s.driveSyncChecking,
    DriveSyncStatus.current => s.driveSyncCurrent,
    DriveSyncStatus.pending => s.driveSyncPending,
    DriveSyncStatus.editing => s.driveSyncEditing,
    DriveSyncStatus.initialChoice => s.driveSyncChoice,
    DriveSyncStatus.conflict => s.driveSyncConflict,
    DriveSyncStatus.unavailable => s.driveSyncUnavailable,
  };
}

class DriveSyncTile extends StatelessWidget {
  const DriveSyncTile({super.key, required this.model});
  final DriveSyncModel model;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      return ListTile(
        leading: const Icon(Icons.cloud_sync_outlined),
        title: Text(s.driveSyncTitle),
        subtitle: Text(driveStatusLabel(s, model)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/drive-sync'),
            builder: (_) => DriveSyncPage(model: model),
          ),
        ),
      );
    },
  );
}

class DriveSyncPage extends StatelessWidget {
  const DriveSyncPage({super.key, required this.model});
  final DriveSyncModel model;

  Future<void> _confirm(
    BuildContext context, {
    DriveBackupCopy? copy,
    bool disable = false,
  }) async {
    final s = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(disable ? s.driveSyncDisable : s.driveSyncTitle),
        content: Text(
          disable ? s.driveSyncDisableWarning : s.driveSyncChooseWarning,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.driveSyncCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.driveSyncConfirm),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    if (disable) {
      await model.disable();
    } else {
      if (copy != null) await model.restore(copy);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      return PopScope(
        canPop: !model.restoring,
        child: Scaffold(
          appBar: AppBar(title: Text(s.driveSyncTitle)),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(s.driveSyncIntro),
              const SizedBox(height: 20),
              Text(
                driveStatusLabel(s, model),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (model.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 16),
              if (!model.enabled)
                FilledButton.icon(
                  onPressed: model.busy ? null : model.enable,
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(s.driveSyncConnect),
                ),
              if (model.enabled) ...[
                OutlinedButton(
                  onPressed: model.busy
                      ? null
                      : () => model.synchronize(interactive: true),
                  child: Text(s.driveSyncRetry),
                ),
                if (model.lastBackupAt != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      s.driveBackupLast(
                        formatRegionalDateTime(
                          model.lastBackupAt!.toLocal(),
                          regionalLocale,
                        ),
                      ),
                    ),
                  ),
                OutlinedButton(
                  onPressed: model.busy ? null : model.refreshCopies,
                  child: Text(s.driveBackupBrowse),
                ),
                if (model.copiesLoaded && model.copies.isEmpty)
                  Text(s.driveBackupEmpty),
                for (final copy in model.copies) ...[
                  const Divider(),
                  Text(
                    copy.legacy
                        ? s.driveBackupLegacy
                        : copy.snapshot.deviceId == model.deviceId
                        ? s.driveSyncThisDevice
                        : s.driveSyncOtherDevice,
                  ),
                  Text(
                    formatRegionalDateTime(
                      copy.snapshot.createdAt.toLocal(),
                      regionalLocale,
                      includeSeconds: true,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: model.busy
                        ? null
                        : () => _confirm(context, copy: copy),
                    child: Text(s.driveSyncUseRemote),
                  ),
                  TextButton(
                    onPressed: model.busy ? null : () => model.exportCopy(copy),
                    child: Text(s.driveSyncExport),
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: model.busy
                      ? null
                      : () => _confirm(context, disable: true),
                  child: Text(s.driveSyncDisable),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class DriveSyncNotice extends StatelessWidget {
  const DriveSyncNotice({super.key, required this.model, required this.child});
  final DriveSyncModel model;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    child: child,
    builder: (context, child) =>
        AbsorbPointer(absorbing: model.applying, child: child),
  );
}
