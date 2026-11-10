import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart' show formatGrams;
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Whether [brew] can be deleted: not when it was archived with its coffee,
/// whose stock still counts its dose (see `deleteBrew`).
bool canDeleteBrew(Brew brew, Coffee? coffee) =>
    coffee?.archivedAtMs == null && brew.archivedByCoffee != true;

/// Asks before deleting [brew], with its curve and photos, and says what
/// happened. A counted dose goes back to its coffee, even when archived.
Future<void> deleteBrewAfterConfirming(
  BuildContext context,
  JournalActions actions,
  Brew brew,
) async {
  final s = AppLocalizations.of(context)!;
  try {
    final returns = await actions.repository.brewStockReturn(brew);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-brew-dialog'),
        title: Text(s.deleteBrewTitle),
        content: Text(
          [
            s.deleteBrewDescription,
            if (brew.stockReviewPending != true) ...[
              if (returns.frozenGrams > 0)
                s.deleteBrewGivesBackFrozen(
                  formatGrams(returns.frozenGrams, regionalLocale.toString()),
                  returns.portionLabel!,
                ),
              if (returns.availableGrams > 0)
                s.deleteBrewGivesBack(
                  formatGrams(
                    returns.availableGrams,
                    regionalLocale.toString(),
                  ),
                ),
            ],
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('delete-brew-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final files = await actions.repository.deleteBrew(brew.id);
    // The deletion is committed; a photo file left behind is harmless, as
    // backups skip files nothing refers to.
    for (final file in files) {
      try {
        await actions.photos?.delete(file);
      } catch (error, stack) {
        reportError(error, stack);
        // Storage may be briefly unavailable.
      }
    }
    actions.message(s.brewDeleted);
  } on BrewArchivedWithCoffeeException {
    actions.message(s.restoreCoffeeFirst);
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) showOperationError(context, error, s.deleteBrewFailed);
  }
}
