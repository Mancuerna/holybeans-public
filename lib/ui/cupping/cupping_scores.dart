import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:intl/intl.dart';

List<String> cuppingLabels(AppLocalizations s) => [
  s.cuppingIntensityAcidity,
  s.cuppingIntensitySweetness,
  s.cuppingIntensityBitterness,
  s.cuppingIntensityBody,
  s.cuppingIntensityAftertaste,
];

String cuppingCupLabel(CuppingModel m, int i, AppLocalizations s) =>
    m.draft.blind
    ? s.cuppingBlindCup(String.fromCharCode(65 + i))
    : s.cuppingCup(i + 1);

String cuppingCoffee(CuppingModel m, int i, AppLocalizations s) =>
    m.draft.blind && !m.draft.revealed
    ? cuppingCupLabel(m, i, s)
    : m.coffees
              .where((c) => c.id == m.draft.cups[i].coffeeId)
              .firstOrNull
              ?.name ??
          s.cuppingDeletedCup;

class CuppingScores extends StatelessWidget {
  const CuppingScores({super.key, required this.model});
  final CuppingModel model;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.cuppingProgress(
                    model.draft.scoredCount,
                    model.draft.cups.length * 6,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('cupping-view'),
                onPressed: model.toggleView,
                icon: Icon(
                  model.matrix
                      ? Icons.view_carousel_outlined
                      : Icons.table_chart_outlined,
                ),
                label: Text(model.matrix ? s.cuppingByCup : s.cuppingMatrix),
              ),
            ],
          ),
        ),
        Expanded(
          child: model.matrix
              ? CuppingMatrix(model: model)
              : _ByCup(model: model),
        ),
      ],
    );
  }
}

class _ByCup extends StatelessWidget {
  const _ByCup({required this.model});
  final CuppingModel model;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final i = model.selected;
    final cup = model.draft.cups[i];
    final labels = cuppingLabels(s);
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var j = 0; j < model.draft.cups.length; j++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('cupping-tab-$j'),
                    label: Text(
                      '${cuppingCupLabel(model, j, s)}${model.draft.cups[j].complete ? " ✓" : ""}',
                    ),
                    selected: i == j,
                    onSelected: (_) => model.select(j),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                cuppingCoffee(model, i, s),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                _equipment(model, i, s),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(s.cuppingScoresHint),
              if (model.missingCups.contains(i))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(s.cuppingDeletedCup),
                ),
              const SizedBox(height: 12),
              CuppingScore(model: model, index: i, label: s.rating),
              for (var score = 0; score < 5; score++) ...[
                const SizedBox(height: 12),
                CuppingScore(
                  model: model,
                  index: i,
                  score: score,
                  label: labels[score],
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey('cupping-notes-$i'),
                initialValue: cup.notes,
                decoration: InputDecoration(labelText: s.notes),
                maxLines: 3,
                maxLength: 10000,
                readOnly: model.scoresLocked,
                onChanged: (v) {
                  if (!model.scoresLocked) model.change(() => cup.notes = v);
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

String _equipment(CuppingModel m, int i, AppLocalizations s) {
  final c = m.draft.cups[i];
  final grinder = m.grinders
      .where((g) => g.id == m.draft.grinderFor(c))
      .firstOrNull;
  final water = m.waters.where((w) => w.id == m.draft.waterFor(c)).firstOrNull;
  return [
    grinder?.name ?? s.preGround,
    if (m.draft.settingFor(c).isNotEmpty) m.draft.settingFor(c),
    water?.name ?? s.noWaterProfile,
  ].join(', ');
}

class CuppingScore extends StatelessWidget {
  const CuppingScore({
    super.key,
    required this.model,
    required this.index,
    required this.label,
    this.score,
  });
  final CuppingModel model;
  final int index;
  final int? score;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cup = model.draft.cups[index];
    final s = AppLocalizations.of(context)!;
    final n = NumberFormat('0.#', regionalLocale.toString());
    final slot = score == null ? 0 : score! + 1;
    final value = cup.notEvaluated[slot]
        ? -1.0
        : score == null
        ? cup.rating
        : cup.scores[score!]?.toDouble();
    final options = score == null
        ? [for (var j = 0; j <= 20; j++) j / 2]
        : [1.0, 2.0, 3.0, 4.0, 5.0];
    return DropdownButtonFormField<double>(
      key: ValueKey('cupping-score-$index-$score-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(child: Text(s.cuppingUnanswered)),
        DropdownMenuItem(value: -1.0, child: Text(s.cuppingNotEvaluated)),
        for (final v in options)
          DropdownMenuItem(value: v, child: Text(n.format(v))),
      ],
      onChanged: model.scoresLocked
          ? null
          : (v) => model.change(() {
              cup.notEvaluated[slot] = v == -1;
              if (score == null) {
                cup.rating = v == -1 ? null : v;
              } else {
                cup.scores[score!] = v == -1 ? null : v?.toInt();
              }
            }),
    );
  }
}

/// One vertical scroll and a horizontal comparison, with cup headings in
/// each cell's semantics and enough room for six cups on a small screen.
class CuppingMatrix extends StatelessWidget {
  const CuppingMatrix({super.key, required this.model});
  final CuppingModel model;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final labels = [s.rating, ...cuppingLabels(s)];
    final width = (190 * MediaQuery.textScalerOf(context).scale(1)).clamp(
      190.0,
      300.0,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.cuppingScoresHint),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: FixedColumnWidth(width),
              children: [
                TableRow(
                  children: [
                    for (var i = 0; i < model.draft.cups.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cuppingCupLabel(model, i, s),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              cuppingCoffee(model, i, s),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _equipment(model, i, s),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (model.missingCups.contains(i))
                              Text(s.cuppingDeletedCup),
                          ],
                        ),
                      ),
                  ],
                ),
                for (var j = 0; j < labels.length; j++)
                  TableRow(
                    children: [
                      for (var i = 0; i < model.draft.cups.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, right: 12),
                          child: Semantics(
                            label: cuppingCupLabel(model, i, s),
                            child: CuppingScore(
                              model: model,
                              index: i,
                              score: j == 0 ? null : j - 1,
                              label: labels[j],
                            ),
                          ),
                        ),
                    ],
                  ),
                TableRow(
                  children: [
                    for (var i = 0; i < model.draft.cups.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, right: 12),
                        child: TextFormField(
                          key: ValueKey('cupping-matrix-notes-$i'),
                          initialValue: model.draft.cups[i].notes,
                          decoration: InputDecoration(labelText: s.notes),
                          maxLines: 3,
                          maxLength: 10000,
                          readOnly: model.scoresLocked,
                          onChanged: (v) {
                            if (!model.scoresLocked) {
                              model.change(() => model.draft.cups[i].notes = v);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
