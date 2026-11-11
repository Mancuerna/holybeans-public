import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/coffee_selection_sheet.dart';
import 'package:holybeans/ui/core/frozen_stock_badge.dart';

class CoffeePicker extends StatefulWidget {
  const CoffeePicker({
    super.key,
    required this.repository,
    required this.coffees,
    required this.value,
    required this.onChanged,
    this.label,
    this.includeArchived = true,
  });

  final JournalRepository repository;
  final List<Coffee> coffees;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? label;
  final bool includeArchived;

  @override
  State<CoffeePicker> createState() => _CoffeePickerState();
}

class _CoffeePickerState extends State<CoffeePicker> {
  late final lots = widget.repository.watchLots();
  late final portions = widget.repository.watchFrozenPortions();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CoffeeLot>>(
    stream: lots,
    builder: (context, lotSnapshot) => StreamBuilder<List<FrozenPortion>>(
      stream: portions,
      builder: (context, portionSnapshot) {
        final s = AppLocalizations.of(context)!;
        final lots = lotSnapshot.data ?? const <CoffeeLot>[];
        final frozen = frozenGramsByCoffee(
          lots,
          portionSnapshot.data ?? const <FrozenPortion>[],
        );
        final fresh = unfrozenGramsByCoffee(lots);
        final chosen = widget.coffees
            .where((c) => c.id == widget.value)
            .firstOrNull;
        Widget badge(Coffee coffee) => FrozenStockBadge(
          key: ValueKey('coffee-frozen-${coffee.id}'),
          state: frozenStockState(fresh[coffee.id], frozen[coffee.id] ?? 0),
        );
        return FormField<String>(
          key: ValueKey('coffee-value-${widget.value}'),
          initialValue: widget.value,
          validator: (value) => value == null ? s.noSelection : null,
          builder: (field) => Semantics(
            button: true,
            child: InkWell(
              key: const ValueKey('brew-coffee-picker'),
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => CoffeeSelectionSheet(
                    coffees: [
                      for (final coffee in widget.coffees)
                        if (widget.includeArchived ||
                            coffee.archivedAtMs == null)
                          coffee,
                    ],
                    selected: widget.value,
                    trailing: badge,
                  ),
                );
                if (!mounted || picked == null) return;
                // The keyed field may have been replaced while the sheet was open.
                if (field.mounted) field.didChange(picked);
                widget.onChanged(picked);
              },
              child: InputDecorator(
                isEmpty: widget.value == null,
                decoration: InputDecoration(
                  labelText: widget.label ?? s.chooseBean,
                  errorText: field.errorText,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chosen?.name ??
                            (widget.value == null ? '' : s.archivedStatus),
                      ),
                    ),
                    if (chosen != null) badge(chosen),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
