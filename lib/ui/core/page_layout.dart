import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Scrolling body of a main tab, padded to clear the floating button.
class JournalPage extends StatelessWidget {
  const JournalPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 112),
    children: children,
  );
}

class JournalListPage extends StatelessWidget {
  const JournalListPage({
    super.key,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
  });

  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 112),
    itemCount: itemCount + 1,
    itemBuilder: (context, index) =>
        index == 0 ? header : itemBuilder(context, index - 1),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(label),
  );
}

/// Search box with a clear button once something is typed.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.label,
    required this.controller,
    this.compact = false,
  });

  final String label;
  final TextEditingController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: label,
      isDense: compact ? true : null,
      contentPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
          : null,
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: AppLocalizations.of(context)!.clearSearch,
              onPressed: controller.clear,
              icon: const Icon(Icons.clear_rounded),
            ),
    ),
  );
}

/// Switches a list between informative and compact cards.
class DensityToggle extends StatelessWidget {
  const DensityToggle({
    super.key,
    required this.compact,
    required this.onPressed,
  });

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return IconButton(
      // The tooltip names the action, so no separate toggle node is needed
      // (a bare Semantics(toggled:) was read as an unlabeled switch).
      tooltip: compact ? strings.showDetailedCards : strings.showCompactCards,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(
        compact ? Icons.view_agenda_outlined : Icons.view_headline_rounded,
      ),
    );
  }
}
