import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/stock_adjustment_labels.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class StockAdjustmentForm extends StatefulWidget {
  const StockAdjustmentForm({
    super.key,
    required this.repository,
    required this.coffee,
    required this.stock,
  });
  final JournalRepository repository;
  final Coffee coffee;
  final CoffeeStock stock;
  @override
  State<StockAdjustmentForm> createState() => _StockAdjustmentFormState();
}

class _StockAdjustmentFormState extends State<StockAdjustmentForm> {
  final amount = TextEditingController();
  final notes = TextEditingController();
  String reason = 'gift';
  String source = '';
  bool busy = false;
  String? error;
  double? get grams => parseNumber(amount.text);
  double? get current => source.isEmpty
      ? widget.stock.remainingGrams
      : [
          ...widget.stock.frozen,
          ...widget.stock.thawed,
        ].where((p) => p.id == source).firstOrNull?.remainingGrams;
  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save(BuildContext formContext) async {
    if (busy) return;
    final s = AppLocalizations.of(context)!;
    final value = grams;
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        (reason != 'correction' && value == 0)) {
      setState(() => error = s.stockAdjustInvalid);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.adjustStock(
        coffeeId: widget.coffee.id,
        reason: reason,
        grams: value,
        frozenPortionId: source.isEmpty ? null : source,
        notes: notes.text,
      );
      if (formContext.mounted) {
        ScaffoldMessenger.of(formContext)
            .showSnackBar(SnackBar(content: Text(s.stockAdjustSaved)));
        FormExitGuard.complete<void>(formContext);
      }
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
    final after = reason == 'correction'
        ? grams
        : current == null || grams == null
        ? null
        : current! - grams!;
    return FormExitGuard(
      hasChanges: () => amount.text.isNotEmpty || notes.text.isNotEmpty,
      busy: () => busy,
      child: Builder(
        builder: (formContext) => Scaffold(
          appBar: AppBar(title: Text(s.stockAdjustTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.coffee.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(s.stockAdjustHelp),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const ValueKey('adjustment-reason'),
                  initialValue: reason,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.stockAdjustReason),
                  items: [
                    for (final value in ['gift', 'waste', 'correction'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(stockAdjustmentReason(s, value)),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          reason = v!;
                          error = null;
                        }),
                ),
                if (widget.stock.frozen.isNotEmpty ||
                    widget.stock.thawed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('adjustment-source'),
                    initialValue: source,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s.stockAdjustSource),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(s.stockAdjustFresh),
                      ),
                      for (final p in [
                        ...widget.stock.frozen,
                        ...widget.stock.thawed,
                      ])
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${s.frozen} · ${p.label} · ${formatGrams(p.remainingGrams, regionalLocale.toString())}',
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            source = v!;
                            error = null;
                          }),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  s.stockAdjustCurrent(
                    current == null
                        ? s.unknownStock
                        : formatGrams(current!, regionalLocale.toString()),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('adjustment-grams'),
                  controller: amount,
                  enabled: !busy,
                  inputFormatters: [decimalInputFormatter],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: reason == 'correction'
                        ? s.stockAdjustMeasured
                        : s.stockAdjustAmount,
                  ),
                  onChanged: (_) => setState(() => error = null),
                ),
                const SizedBox(height: 12),
                if (after != null && after.isFinite && after >= 0)
                  Text(
                    s.stockAdjustResult(
                      formatGrams(after, regionalLocale.toString()),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('adjustment-notes'),
                  controller: notes,
                  enabled: !busy,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.notes),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('save-adjustment'),
                  onPressed: busy ? null : () => save(formContext),
                  child: Text(s.save),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => FormExitGuard.cancel(formContext),
                  child: Text(s.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
