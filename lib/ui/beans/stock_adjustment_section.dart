import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/stock_adjustment_form.dart';
import 'package:holybeans/ui/beans/stock_adjustment_labels.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

class StockAdjustmentSection extends StatelessWidget {
  const StockAdjustmentSection({
    super.key,
    required this.repository,
    required this.coffee,
    required this.stock,
    required this.adjustments,
  });
  final JournalRepository repository;
  final Coffee coffee;
  final CoffeeStock stock;
  final List<StockAdjustment> adjustments;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final operations = <String, List<StockAdjustment>>{};
    for (final row in adjustments) {
      operations.putIfAbsent(row.operationId, () => []).add(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (coffee.archivedAtMs == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('adjust-stock'),
              icon: const Icon(Icons.balance_rounded),
              label: Text(s.stockAdjustTitle),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => StockAdjustmentForm(
                    repository: repository,
                    coffee: coffee,
                    stock: stock,
                  ),
                ),
              ),
            ),
          ),
        if (operations.isNotEmpty)
          ExpansionTile(
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            key: const ValueKey('stock-adjustment-history'),
            tilePadding: EdgeInsets.zero,
            title: Text(s.stockAdjustHistory),
            children: [
              for (final rows in operations.values)
                _AdjustmentRow(
                  key: ValueKey(rows.first.operationId),
                  repository: repository,
                  rows: rows,
                  active: coffee.archivedAtMs == null,
                ),
            ],
          ),
      ],
    );
  }
}

class _AdjustmentRow extends StatefulWidget {
  const _AdjustmentRow({
    super.key,
    required this.repository,
    required this.rows,
    required this.active,
  });
  final JournalRepository repository;
  final List<StockAdjustment> rows;
  final bool active;
  @override
  State<_AdjustmentRow> createState() => _AdjustmentRowState();
}

class _AdjustmentRowState extends State<_AdjustmentRow> {
  bool busy = false;
  String? error;
  Future<void> undo() async {
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.stockAdjustUndoTitle),
        content: Text(s.stockAdjustUndoBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.undo),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.undoStockAdjustment(
        widget.rows.first.operationId,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = journalWriteErrorText(
            context,
            e,
            stockAdjustmentError(s, e),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final row = widget.rows.first;
    final unknown = widget.rows.any((r) => r.previousGrams == null);
    final delta = widget.rows.fold<double>(
      0,
      (sum, r) => sum + r.resultingGrams - (r.previousGrams ?? 0),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stockAdjustmentReason(s, row.reason)} · ${unknown ? s.stockAdjustCurrent(formatGrams(widget.rows.fold<double>(0, (sum, r) => sum + r.resultingGrams), regionalLocale.toString())) : '${delta > 0 ? '+' : ''}${formatGrams(delta, regionalLocale.toString())}'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            formatRegionalDateTime(
              DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
              regionalLocale,
            ),
          ),
          if (row.frozenPortionId != null) Text(s.frozen),
          if (row.notes != null) Text(row.notes!),
          if (row.reversedAtMs != null)
            Text(s.stockAdjustReversed)
          else if (widget.active)
            TextButton(onPressed: busy ? null : undo, child: Text(s.undo)),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
