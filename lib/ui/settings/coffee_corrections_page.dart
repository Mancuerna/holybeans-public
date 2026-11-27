import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_corrections.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/correction_review_page.dart';

typedef _CorrectionData = ({
  Map<String, List<CorrectionRow>> groups,
  List<String> names,
});

class CoffeeCorrectionsPage extends StatefulWidget {
  const CoffeeCorrectionsPage({
    super.key,
    required this.database,
    required this.exportBackup,
  });
  final AppDatabase database;
  final Future<void> Function() exportBackup;

  @override
  State<CoffeeCorrectionsPage> createState() => _CoffeeCorrectionsPageState();
}

class _CoffeeCorrectionsPageState extends State<CoffeeCorrectionsPage> {
  late final repo = CoffeeCorrections(widget.database);
  CorrectionField field = CorrectionField.country;
  bool archived = false;
  bool backingUp = false;
  String query = '';
  final selected = <String>{};
  late Future<_CorrectionData> data = load();

  Future<_CorrectionData> load() async {
    final groups = <String, List<CorrectionRow>>{};
    for (final row in await repo.rows(field, archived: archived)) {
      (groups[row.value] ??= []).add(row);
    }
    return (
      groups: groups,
      names: field == CorrectionField.roaster
          ? await repo.roasterNames()
          : <String>[],
    );
  }

  void refresh() {
    selected.clear();
    data = load();
  }

  Future<void> backup() async {
    setState(() => backingUp = true);
    try {
      await widget.exportBackup();
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).backupFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => backingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final labels = {
      CorrectionField.country: s.country,
      CorrectionField.region: s.region,
      CorrectionField.farm: s.farm,
      CorrectionField.producer: s.producer,
      CorrectionField.variety: s.variety,
      CorrectionField.process: s.process,
      CorrectionField.roaster: s.roaster,
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.correctCoffees)),
      body: FutureBuilder(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.correctionLoadFailed),
                  TextButton(
                    onPressed: () => setState(refresh),
                    child: Text(s.retry),
                  ),
                ],
              ),
            );
          }
          final (:groups, :names) = snapshot.requireData;
          final foldedQuery = foldCountryName(query);
          final values =
              groups.keys
                  .where((v) => foldCountryName(v).contains(foldedQuery))
                  .toList()
                ..sort();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 1 + (values.isEmpty ? 1 : values.length),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.correctionBackup),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: backingUp ? null : backup,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(s.exportBackup),
                      ),
                    ),
                    DropdownButton<CorrectionField>(
                      value: field,
                      isExpanded: true,
                      items: [
                        for (final entry in labels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (next) {
                        if (next != null) {
                          setState(() {
                            field = next;
                            query = '';
                            refresh();
                          });
                        }
                      },
                    ),
                    SwitchListTile(
                      title: Text(s.correctionArchived),
                      value: archived,
                      onChanged: (v) => setState(() {
                        archived = v;
                        refresh();
                      }),
                    ),
                    TextFormField(
                      key: ValueKey(field),
                      initialValue: query,
                      decoration: InputDecoration(labelText: s.search),
                      onChanged: (v) => setState(() => query = v),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty || backingUp
                          ? null
                          : () async {
                              final result = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => CorrectionReviewPage(
                                        repo: repo,
                                        field: field,
                                        rows: [
                                          for (final value in selected)
                                            ...groups[value]!,
                                        ],
                                        suggestions: {
                                          ...names,
                                          ...groups.keys,
                                          if (field == CorrectionField.country)
                                            for (final c in coffeeCountries)
                                              c.nameFor(s.localeName),
                                        }.toList()..sort(),
                                      ),
                                    ),
                                  );
                              if (!mounted || result == null) return;
                              setState(refresh);
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result
                                        ? s.correctionSaved
                                        : s.correctionConflict,
                                  ),
                                ),
                              );
                            },
                      child: Text(s.correctionReview),
                    ),
                  ],
                );
              }
              if (values.isEmpty) {
                return ListTile(title: Text(s.correctionEmpty));
              }
              final value = values[i - 1];
              return CheckboxListTile(
                title: Text(value),
                subtitle: Text(
                  s.correctionCount(
                    groups[value]!.map((r) => r.coffeeId).toSet().length,
                  ),
                ),
                value: selected.contains(value),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    selected.add(value);
                  } else {
                    selected.remove(value);
                  }
                }),
              );
            },
          );
        },
      ),
    );
  }
}
