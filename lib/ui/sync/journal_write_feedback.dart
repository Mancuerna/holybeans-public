import 'package:flutter/material.dart';
import 'package:holybeans/data/database/journal_write_gate.dart';
import 'package:holybeans/l10n/app_localizations.dart';

String journalWriteErrorText(
  BuildContext context,
  Object? error,
  String fallback,
) {
  if (error is! JournalReadOnlyException) return fallback;
  final s = AppLocalizations.of(context);
  return s.driveWriteChecking;
}

void showOperationError(BuildContext context, Object error, String fallback) {
  if (!context.mounted) return;
  if (error is! JournalReadOnlyException) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(fallback)));
    return;
  }
  final s = AppLocalizations.of(context);
  final message = journalWriteErrorText(context, error, fallback);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(fallback),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(s.driveWriteDismiss),
        ),
      ],
    ),
  );
}
