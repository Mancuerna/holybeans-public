import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Coffees to filter by, in use first and then finished, each group by
/// name, with a search on the name and roaster.
class CoffeeSelectionSheet extends StatefulWidget {
  const CoffeeSelectionSheet({
    super.key,
    required this.coffees,
    this.allowAny = false,
    this.selected,
    this.trailing,
  });

  final List<Coffee> coffees;
  final bool allowAny;
  final String? selected;
  final Widget Function(Coffee)? trailing;

  @override
  State<CoffeeSelectionSheet> createState() => _CoffeeSelectionSheetState();
}

class _CoffeeSelectionSheetState extends State<CoffeeSelectionSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final needle = foldSuggestion(query);
    final matches =
        widget.coffees
            .where(
              (coffee) =>
                  needle.isEmpty ||
                  foldSuggestion('${coffee.name} ${coffee.roaster}')
                      .contains(needle),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final active = [
      for (final coffee in matches)
        if (coffee.archivedAtMs == null) coffee,
    ];
    final archived = [
      for (final coffee in matches)
        if (coffee.archivedAtMs != null) coffee,
    ];
    Widget tile(Coffee coffee) => ListTile(
      key: ValueKey(
        '${widget.allowAny ? 'history-bean-choice' : 'coffee-choice'}-${coffee.id}',
      ),
      selected: coffee.id == widget.selected,
      trailing: widget.trailing?.call(coffee),
      title: Text(coffee.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: coffee.roaster.trim().isEmpty ? null : Text(coffee.roaster),
      onTap: () => Navigator.pop(context, coffee.id),
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                key: ValueKey(
                  widget.allowAny
                      ? 'history-bean-search'
                      : 'brew-coffee-search',
                ),
                decoration: InputDecoration(
                  labelText: s.search,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowAny && needle.isEmpty)
                    ListTile(
                      title: Text(s.anyBean),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(s.noMatchingBeans),
                    ),
                  if (active.isNotEmpty) ...[
                    header(s.beansAvailable),
                    ...active.map(tile),
                  ],
                  if (archived.isNotEmpty) ...[
                    header(s.beansArchived),
                    ...archived.map(tile),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
