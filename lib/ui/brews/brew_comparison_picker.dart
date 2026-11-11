import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
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
  var second = await showModalBottomSheet<Brew>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _ComparisonPicker(first: first, data: data, actions: actions),
  );
  if (second == null || !context.mounted) return;
  try {
    first = await actions.read.queries.brew(first.id) ?? first;
    second = await actions.read.queries.brew(second.id) ?? second;
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) {
      actions.navigation.message(AppLocalizations.of(context)!.dataError);
    }
    return;
  }
  if (!context.mounted) return;
  // A is the earlier brew, so "B − A" reads as what changed since.
  final (a, b) = first.brewedAtMs <= second.brewedAtMs
      ? (first, second)
      : (second, first);
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          BrewComparisonPage(a: a, b: b, data: data, actions: actions.read),
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
  List<Brew>? candidates;
  List<Brew> rows = [];
  Object? error;
  bool loading = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.data.reads == null) {
      candidates = widget.data.brews;
      _filter();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.data.reads!.analytics();
      if (!mounted) return;
      candidates = loaded;
      _filter();
    } catch (failure, stack) {
      reportError(failure, stack);
      if (mounted) {
        setState(() {
          error = failure;
          loading = false;
        });
      }
    }
  }

  void _filter() {
    if (candidates == null) return;
    final input = (
      brews: candidates!,
      coffees: widget.data.coffees,
      first: widget.first,
      query: query,
    );
    final current = ++generation;
    if (candidates!.length <= 200) {
      setState(() {
        rows = _comparisonRows(input);
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    unawaited(
      compute(_comparisonRows, input)
          .then((result) {
            if (mounted && current == generation) {
              setState(() {
                rows = result;
                loading = false;
              });
            }
          })
          .catchError((Object failure, StackTrace stack) {
            reportError(failure, stack);
            if (mounted && current == generation) {
              setState(() {
                error = failure;
                loading = false;
              });
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final names = {
      for (final coffee in widget.data.coffees) coffee.id: coffee.name,
    };
    String name(Brew brew) => names[brew.coffeeId] ?? '—';
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
                  onChanged: (value) {
                    query = value;
                    _filter();
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: error != null
                    ? Center(
                        child: TextButton(
                          onPressed: _load,
                          child: Text(s.dataError),
                        ),
                      )
                    : loading
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
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
                                  widget.actions.read.methods,
                                  regionalLocale.toString(),
                                  hidden: widget.actions.read.hiddenParameters,
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

List<Brew> _comparisonRows(
  ({List<Brew> brews, List<Coffee> coffees, Brew first, String query}) input,
) {
  final names = {for (final coffee in input.coffees) coffee.id: coffee.name};
  final needle = foldSuggestion(input.query);
  int closeness(Brew brew) =>
      (brew.coffeeId == input.first.coffeeId ? 2 : 0) +
      (brew.methodName == input.first.methodName ? 1 : 0);
  return input.brews
      .where(
        (brew) =>
            brew.id != input.first.id &&
            foldSuggestion('${names[brew.coffeeId] ?? '—'} ${brew.methodName}')
                .contains(needle),
      )
      .toList()
    ..sort((a, b) {
      final nearby = closeness(b).compareTo(closeness(a));
      return nearby != 0 ? nearby : b.brewedAtMs.compareTo(a.brewedAtMs);
    });
}
