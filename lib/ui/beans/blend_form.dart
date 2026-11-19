import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/archive_dialog.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

Future<void> openBlendForm(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
) async {
  final s = AppLocalizations.of(context);
  final eligible = {
    for (final c in coffees)
      if (c.archivedAtMs == null && c.mixedAtMs == null) c.id: c,
  };
  final empty = await Navigator.push<List<Coffee>>(
    context,
    MaterialPageRoute(
      builder: (_) => _BlendForm(actions: actions, coffees: eligible),
    ),
  );
  if (!context.mounted || empty == null) return;
  actions.navigation.message(s.beanSaved);
  if (empty.isEmpty) return;
  try {
    final averages = {
      for (final c in empty)
        c.id: await actions.read.queries.coffeeRatings(c.id),
    };
    if (!context.mounted) return;
    final ratings = {for (final c in empty) c.id: c.rating};
    if (empty.length == 1) {
      final coffee = empty.single;
      final result = await showDialog<CoffeeArchiveDecision>(
        context: context,
        builder: (_) => CoffeeArchiveDialog(
          coffeeName: coffee.name,
          initialRating: coffee.rating,
          afterOverdraw: false,
          reason: s.blendArchivePrompt,
          brewRatings: averages[coffee.id]!,
        ),
      );
      if (result == null) return;
      ratings[coffee.id] = result.rating;
    } else {
      final selected = ratings.keys.toSet();
      final archive = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (_, update) => AlertDialog(
            title: Text(s.blendArchiveSelected),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.blendArchivePrompt),
                  for (final coffee in empty) ...[
                    CheckboxListTile(
                      title: Text(coffee.name),
                      value: selected.contains(coffee.id),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          selected.add(coffee.id);
                        } else {
                          selected.remove(coffee.id);
                        }
                      }),
                    ),
                    if (selected.contains(coffee.id))
                      CoffeeArchiveRating(
                        rating: ratings[coffee.id],
                        brewRatings: averages[coffee.id]!,
                        onChanged: (v) => update(() => ratings[coffee.id] = v),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(s.blendArchiveSelected),
              ),
            ],
          ),
        ),
      );
      if (archive != true) return;
      ratings.removeWhere((id, _) => !selected.contains(id));
    }
    await actions.commands.mutations.archiveEmptySources(ratings);
  } catch (e) {
    if (context.mounted) showOperationError(context, e, s.saveFailed);
  }
}

class _BlendForm extends StatefulWidget {
  const _BlendForm({required this.actions, required this.coffees});
  final JournalActions actions;
  final Map<String, Coffee> coffees;
  @override
  State<_BlendForm> createState() => _BlendFormState();
}

class _BlendFormState extends State<_BlendForm> {
  final amounts = <String, TextEditingController>{};
  final selected = <String>{};
  String? name;
  bool saving = false;
  late final lotsStream = widget.actions.read.queries.watchLots();
  @override
  void dispose() {
    for (final c in amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save(String title, Map<String, double> grams) async {
    if (saving) return;
    setState(() => saving = true);
    final s = AppLocalizations.of(context);
    try {
      final result = await widget.actions.commands.mutations.createBlend(
        title,
        grams,
      );
      if (mounted) Navigator.pop(context, result.empty);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showOperationError(context, e, s.stockAdjustChanged);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final locale = regionalLocale.toString();
    return Scaffold(
      appBar: AppBar(title: Text(s.createBlend)),
      body: SafeArea(
        child: StreamBuilder<List<CoffeeLot>>(
          stream: lotsStream,
          initialData: widget.actions.read.latestLots,
          builder: (_, snapshot) {
            final lots = [
              for (final l in snapshot.data ?? <CoffeeLot>[])
                if (widget.coffees.containsKey(l.coffeeId) &&
                    l.archivedAtMs == null &&
                    (l.remainingGrams ?? 0) > 0)
                  l,
            ];
            final grams = <String, double>{};
            final ids = <String>{};
            for (final l in lots.where((l) => selected.contains(l.id))) {
              final value = double.tryParse(
                amounts[l.id]!.text.replaceAll(',', '.'),
              );
              if (value != null &&
                  value > 0 &&
                  value <= l.remainingGrams! &&
                  (value * 1000 - (value * 1000).round()).abs() < 0.000001) {
                grams[l.id] = value;
                ids.add(l.coffeeId);
              }
            }
            final title = (name ?? s.bagEnds).trim();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  initialValue: s.bagEnds,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: s.beanName),
                  onChanged: (v) => setState(() => name = v),
                ),
                Text(s.blendSelectSources),
                for (final l in lots) ...[
                  CheckboxListTile(
                    title: Text(widget.coffees[l.coffeeId]!.name),
                    subtitle: Text(
                      [
                        if (l.roastDate != null) l.roastDate!,
                        formatGrams(l.remainingGrams!, locale),
                      ].join(' · '),
                    ),
                    value: selected.contains(l.id),
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              selected.add(l.id);
                              amounts.putIfAbsent(
                                l.id,
                                () => TextEditingController(
                                  text: l.remainingGrams.toString(),
                                ),
                              );
                            } else {
                              selected.remove(l.id);
                            }
                          }),
                  ),
                  if (selected.contains(l.id))
                    TextField(
                      controller: amounts[l.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: widget.coffees[l.coffeeId]!.name,
                        suffixText: 'g',
                        errorText: grams.containsKey(l.id)
                            ? null
                            : s.stockAdjustInvalid,
                      ),
                    ),
                ],
                TextButton(
                  onPressed: selected.isEmpty || saving
                      ? null
                      : () => setState(() {
                          for (final l in lots.where(
                            (l) => selected.contains(l.id),
                          )) {
                            amounts[l.id]!.text = l.remainingGrams.toString();
                          }
                        }),
                  child: Text(s.blendUseAll),
                ),
                FilledButton(
                  onPressed:
                      !saving &&
                          title.isNotEmpty &&
                          ids.length >= 2 &&
                          grams.length ==
                              lots
                                  .where((lot) => selected.contains(lot.id))
                                  .length
                      ? () => save(title, grams)
                      : null,
                  child: Text(
                    '${s.createBlend} · ${formatGrams(grams.values.fold<double>(0, (a, b) => a + b), locale)}',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
