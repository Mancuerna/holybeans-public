import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/coffee_corrections.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class CorrectionReviewPage extends StatefulWidget {
  const CorrectionReviewPage({
    super.key,
    required this.repo,
    required this.field,
    required this.rows,
    required this.suggestions,
  });
  final CoffeeCorrections repo;
  final CorrectionField field;
  final List<CorrectionRow> rows;
  final List<String> suggestions;
  @override
  State<CorrectionReviewPage> createState() => _CorrectionReviewPageState();
}

class _CorrectionReviewPageState extends State<CorrectionReviewPage> {
  late final selected = widget.rows.toSet();
  String target = '';
  bool busy = false;
  bool get roaster => widget.field == CorrectionField.roaster;
  void change(String value) =>
      setState(() => target = roaster ? roasterName(value) : value.trim());

  Future<void> save(Set<CorrectionRow> changes) async {
    setState(() => busy = true);
    try {
      await widget.repo.apply(widget.field, changes, target);
      if (mounted) Navigator.pop(context, true);
    } on CorrectionConflict {
      if (mounted) Navigator.pop(context, false);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).saveFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final changes = selected.where((r) => r.value != target).toSet();
    final counts = [
      if (!roaster) s.correctionOrigins(changes.length),
      s.correctionCount(changes.map((r) => r.coffeeId).toSet().length),
    ];
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.correctionReview)),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: widget.rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: target),
                    optionsBuilder: (v) {
                      final q = foldCountryName(v.text);
                      return widget.suggestions.where(
                        (name) => foldCountryName(name).contains(q),
                      );
                    },
                    onSelected: change,
                    fieldViewBuilder: (context, controller, focus, onSubmit) =>
                        TextField(
                          controller: controller,
                          focusNode: focus,
                          enabled: !busy,
                          maxLength: roaster ? 200 : null,
                          decoration: InputDecoration(
                            labelText: s.correctionTarget,
                          ),
                          onTapOutside: (_) => focus.unfocus(),
                          onChanged: change,
                          onSubmitted: (_) => onSubmit(),
                        ),
                  ),
                  Text(counts.join(' · ')),
                  FilledButton(
                    onPressed:
                        busy ||
                            target.isEmpty ||
                            changes.isEmpty ||
                            (roaster && target.length > 200)
                        ? null
                        : () => save(changes),
                    child: Text(s.save),
                  ),
                ],
              );
            }
            final row = widget.rows[i - 1];
            return CheckboxListTile(
              title: Text(row.name),
              subtitle: Text(
                [
                  if (row.archived) s.archivedStatus,
                  if (row.position case final int p) s.correctionOrigin(p + 1),
                  target.isEmpty ? row.value : '${row.value} → $target',
                ].join(' · '),
              ),
              value: changes.contains(row),
              onChanged: busy || row.value == target
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(row);
                      } else {
                        selected.remove(row);
                      }
                    }),
            );
          },
        ),
      ),
    );
  }
}
