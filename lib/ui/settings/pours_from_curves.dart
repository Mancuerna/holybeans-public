import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Finds the filter brews whose scale curve shows their blooms and pours
/// but has none recorded, and fills them all after confirming. What was
/// written by hand, including a number of blooms, is kept.
Future<void> fillPoursFromCurves(
  BuildContext context, {
  required JournalRepository repository,
  required ValueChanged<String> message,
}) async {
  final s = AppLocalizations.of(context);
  final List<({Brew brew, BrewPours pours})> found;
  try {
    found = await repository.poursFromCurves();
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) showOperationError(context, error, s.dataError);
    return;
  }
  if (!context.mounted) return;
  if (found.isEmpty) {
    message(s.poursFromCurvesNone);
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.poursFromCurvesTitle),
      content: Text(s.poursFromCurvesConfirm(found.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          key: const ValueKey('pours-from-curves-fill'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(s.poursFromCurvesFill),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await repository.savePoursFromCurves(found);
    message(s.poursFromCurvesDone(found.length));
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) showOperationError(context, error, s.saveFailed);
  }
}
