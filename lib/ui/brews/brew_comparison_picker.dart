import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

Future<void> showBrewComparison(
  BuildContext context,
  JournalActions actions,
  Brew first,
  JournalData data,
) async {
  final second = await showModalBottomSheet<Brew>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _ComparisonPicker(first: first, data: data, actions: actions),
  );
  if (second == null || !context.mounted) return;
  // A is the earlier brew, so "B − A" reads as what changed since.
  final (a, b) = first.brewedAtMs <= second.brewedAtMs
      ? (first, second)
      : (second, first);
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          BrewComparisonPage(a: a, b: b, data: data, actions: actions),
    ),
  );
}

class _ComparisonPicker extends StatefulWidget {
  const _ComparisonPicker({
    required this.first,
    required this.data,
    required this.actions,
  });
  final Brew first;
  final JournalData data;
  final JournalActions actions;

  @override
  State<_ComparisonPicker> createState() => _ComparisonPickerState();
}

class _ComparisonPickerState extends State<_ComparisonPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    String name(Brew brew) =>
        widget.data.coffees
            .where((coffee) => coffee.id == brew.coffeeId)
            .firstOrNull
            ?.name ??
        '—';
    final rows =
        widget.data.brews
            .where(
              (brew) =>
                  brew.id != widget.first.id &&
                  foldSuggestion('${name(brew)} ${brew.methodName}')
                      .contains(foldSuggestion(query)),
            )
            .toList()
          ..sort((a, b) {
            // Same coffee and method first (a dial-in), then the same
            // coffee, then the same method, each newest first.
            int closeness(Brew brew) =>
                (brew.coffeeId == widget.first.coffeeId ? 2 : 0) +
                (brew.methodName == widget.first.methodName ? 1 : 0);
            final byCloseness = closeness(b).compareTo(closeness(a));
            if (byCloseness != 0) return byCloseness;
            return b.brewedAtMs.compareTo(a.brewedAtMs);
          });
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  s.chooseComparisonBrew,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const ValueKey('comparison-search'),
                  decoration: InputDecoration(
                    labelText: s.comparisonSearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(s.comparisonNoCandidates),
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final brew = rows[index];
                          return ListTile(
                            key: ValueKey('compare-with-${brew.id}'),
                            title: Text(name(brew)),
                            subtitle: Text(
                              [
                                brew.methodName,
                                formatBrewTimestamp(brew, regionalLocale),
                                ?brewRecipeLine(
                                  brew,
                                  widget.actions.methods,
                                  regionalLocale.toString(),
                                  hidden: widget.actions.hiddenParameters,
                                ),
                                if (brew.archivedAtMs != null) s.archivedStatus,
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            onTap: () => Navigator.pop(context, brew),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
