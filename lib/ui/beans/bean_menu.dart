import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/share_bean_flow.dart';
import 'package:holybeans/ui/labels/label_print_flow.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Actions for a bean card, with deletion available only before its first brew.
class BeanMenu extends StatelessWidget {
  const BeanMenu({
    super.key,
    required this.coffee,
    required this.hasBrews,
    required this.actions,
  });

  final Coffee coffee;
  final bool hasBrews;
  final JournalActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      key: ValueKey('bean-menu-${coffee.id}'),
      tooltip: s.moreOptions,
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(s.editBean)),
        PopupMenuItem(
          key: const ValueKey('bean-share-card'),
          value: 'share',
          child: Text(s.shareBeanCard),
        ),
        PopupMenuItem(
          key: const ValueKey('bean-print-label'),
          value: 'print-label',
          child: Text(s.labelPrint),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(
            coffee.archivedAtMs == null ? s.archiveBean : s.unarchiveBean,
          ),
        ),
        if (!hasBrews)
          PopupMenuItem(value: 'delete', child: Text(s.deleteBean)),
      ],
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await actions.navigation.addCoffee(coffee);
          case 'share':
            if (context.mounted) {
              await showShareBeanSheet(context, actions, coffee);
            }
          case 'print-label':
            if (context.mounted) {
              await showCoffeeLabelPage(context, actions, coffee);
            }
          case 'archive':
            if (coffee.archivedAtMs == null) {
              await actions.commands.confirmCoffeeArchive(coffee);
            } else {
              try {
                await actions.commands.mutations.setCoffeeArchived(
                  coffee.id,
                  archived: false,
                );
              } catch (error, stack) {
                reportError(error, stack);
                if (context.mounted) {
                  showOperationError(context, error, s.saveFailed);
                }
              }
            }
          case 'delete':
            if (context.mounted) await _delete(context, s);
        }
      },
    );
  }

  Future<void> _delete(BuildContext context, AppLocalizations s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-bean-dialog'),
        title: Text(s.deleteBeanTitle),
        content: Text(s.deleteBeanDescription(coffee.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('delete-bean-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final files = await actions.commands.mutations.deleteUnusedCoffee(
        coffee.id,
      );
      // The database deletion is committed. A file-system failure should not
      // report that the coffee still exists; backups omit unreferenced files.
      for (final file in files) {
        try {
          await actions.read.photos?.delete(file);
        } catch (error, stack) {
          reportError(error, stack);
          // An orphan can remain if storage is temporarily unavailable.
        }
      }
      actions.navigation.message(s.beanDeleted);
    } on CoffeeHasBrewsException {
      actions.navigation.message(s.deleteBeanHasBrews);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) {
        showOperationError(context, error, s.deleteBeanFailed);
      }
    }
  }
}
