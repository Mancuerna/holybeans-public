import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

class CoffeeDetailsHeader extends StatefulWidget {
  const CoffeeDetailsHeader({
    super.key,
    required this.navigation,
    required this.commands,
    required this.coffee,
  });

  final JournalNavigation navigation;
  final JournalCommands commands;
  final Coffee coffee;

  @override
  State<CoffeeDetailsHeader> createState() => _CoffeeDetailsHeaderState();
}

class _CoffeeDetailsHeaderState extends State<CoffeeDetailsHeader> {
  late bool favorite = widget.coffee.isFavorite;

  Future<void> _toggleFavorite() async {
    final s = AppLocalizations.of(context);
    final next = !favorite;
    setState(() => favorite = next);
    try {
      await widget.commands.mutations.setCoffeeFavorite(
        widget.coffee.id,
        favorite: next,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => favorite = !next);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  Future<void> _toggleArchive() async {
    final s = AppLocalizations.of(context);
    final commands = widget.commands;
    final coffee = widget.coffee;
    if (coffee.archivedAtMs == null) {
      final archived = await commands.confirmCoffeeArchive(coffee);
      if (archived && mounted) Navigator.pop(context);
      return;
    }
    try {
      await commands.mutations.setCoffeeArchived(coffee.id, archived: false);
      if (mounted) Navigator.pop(context);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final coffee = widget.coffee;
    final archived = coffee.archivedAtMs != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailHeader(
          title: coffee.name,
          subtitle: archived ? s.archivedStatus : '',
          actions: [
            IconButton(
              key: const ValueKey('bean-detail-favorite'),
              tooltip: favorite ? s.removeFavorite : s.addFavorite,
              isSelected: favorite,
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: const Icon(Icons.favorite_rounded),
              onPressed: _toggleFavorite,
            ),
            IconButton(
              key: const ValueKey('bean-detail-edit'),
              tooltip: s.editBean,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                // Saved or cancelled, the edit comes back to the details.
                final navigation = widget.navigation;
                Navigator.pop(context);
                await navigation.addCoffee(coffee);
                navigation.showCoffeeDetailsById(coffee.id);
              },
            ),
            IconButton(
              key: const ValueKey('bean-detail-archive'),
              tooltip: archived ? s.unarchiveBean : s.archiveBean,
              icon: Icon(
                archived
                    ? Icons.unarchive_outlined
                    : Icons.inventory_2_outlined,
              ),
              onPressed: _toggleArchive,
            ),
          ],
        ),
        if (coffee.roaster.trim().isNotEmpty)
          TextButton.icon(
            key: const ValueKey('bean-detail-roaster'),
            icon: const Icon(Icons.storefront_outlined),
            label: Text(coffee.roaster),
            onPressed: () =>
                widget.navigation.showRoasters(roaster: coffee.roaster),
          ),
      ],
    );
  }
}
