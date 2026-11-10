import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

Future<void> deleteEquipmentAfterConfirming(
  BuildContext context, {
  required String name,
  required Future<List<EquipmentDeletionBlocker>> Function() check,
  required Future<void> Function() delete,
}) async {
  final s = AppLocalizations.of(context)!;
  try {
    final blockers = await check();
    if (!context.mounted) return;
    if (blockers.isNotEmpty) {
      await _showBlockers(context, name, blockers);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-equipment-dialog'),
        scrollable: true,
        title: Text(s.deleteEquipmentTitle(name)),
        content: Text(s.deleteEquipmentDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('delete-equipment-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The repository checks again in the deletion transaction.
    await delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.equipmentDeleted(name))));
    }
  } on EquipmentInUseException catch (error) {
    if (context.mounted) await _showBlockers(context, name, error.blockers);
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) {
      showOperationError(context, error, s.deleteEquipmentFailed);
    }
  }
}

Future<void> _showBlockers(
  BuildContext context,
  String name,
  List<EquipmentDeletionBlocker> blockers,
) {
  final s = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('equipment-in-use-dialog'),
      scrollable: true,
      title: Text(s.equipmentInUseTitle(name)),
      content: Text(
        [
          for (final blocker in blockers)
            switch (blocker) {
              EquipmentDeletionBlocker.brews => s.equipmentUsedByBrews,
              EquipmentDeletionBlocker.tools => s.equipmentUsedByTools,
              EquipmentDeletionBlocker.machine => s.equipmentUsedByMachine,
              EquipmentDeletionBlocker.recipient => s.equipmentUsedByRecipient,
              EquipmentDeletionBlocker.cupping => s.equipmentUsedByCupping,
            },
          s.equipmentArchiveInstead,
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
      ],
    ),
  );
}
