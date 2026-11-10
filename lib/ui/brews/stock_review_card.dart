import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class StockReviewCard extends StatefulWidget {
  const StockReviewCard({
    super.key,
    required this.repository,
    required this.brew,
    required this.onResolved,
  });
  final JournalRepository repository;
  final Brew brew;
  final ValueChanged<Brew> onResolved;
  @override
  State<StockReviewCard> createState() => _StockReviewCardState();
}

class _StockReviewCardState extends State<StockReviewCard> {
  bool busy = false;
  bool failed = false;
  Future<void> resolve(bool deduct) async {
    if (busy) return;
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.stockReviewTitle),
        content: Text(
          deduct ? s.stockReviewConfirmDeduct : s.stockReviewConfirmKeep,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.stockReviewConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await widget.repository.resolveBrewStockReview(
        widget.brew.id,
        deduct: deduct,
      );
      final updated = await widget.repository.brew(widget.brew.id);
      if (mounted && updated != null) widget.onResolved(updated);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.stockReviewTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(s.stockReviewBody),
            if (failed) Text(s.stockReviewFailed),
            TextButton(
              key: const ValueKey('stock-review-keep'),
              onPressed: busy ? null : () => resolve(false),
              child: Text(s.stockReviewKeep),
            ),
            OutlinedButton(
              key: const ValueKey('stock-review-deduct'),
              onPressed:
                  busy ||
                      widget.brew.lotId == null ||
                      widget.brew.doseGrams == null
                  ? null
                  : () => resolve(true),
              child: Text(s.stockReviewDeduct),
            ),
          ],
        ),
      ),
    );
  }
}
