import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Date and time of a brew as two chips that open the pickers.
class BrewDateTimeChips extends StatelessWidget {
  const BrewDateTimeChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _chooseDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      locale: regionalLocale,
      initialDate: value,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (selected == null ||
        (selected.year == value.year &&
            selected.month == value.month &&
            selected.day == value.day)) {
      return;
    }
    onChanged(
      DateTime(
        selected.year,
        selected.month,
        selected.day,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      ),
    );
  }

  Future<void> _chooseTime(BuildContext context) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (selected == null ||
        (selected.hour == value.hour && selected.minute == value.minute)) {
      return;
    }
    onChanged(
      DateTime(
        value.year,
        value.month,
        value.day,
        selected.hour,
        selected.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          key: const ValueKey('brew-date-chip'),
          tooltip: s.brewDate,
          avatar: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(formatRegionalDate(value, regionalLocale)),
          onPressed: () => _chooseDate(context),
        ),
        ActionChip(
          key: const ValueKey('brew-time-chip'),
          tooltip: s.brewTime,
          avatar: const Icon(Icons.schedule_outlined, size: 18),
          label: Text(
            regionalTimeFormat(regionalLocale.toString()).format(value),
          ),
          onPressed: () => _chooseTime(context),
        ),
      ],
    );
  }
}

/// A catalog dropdown with a button to add a new entry next to it.
class DropdownWithAdd extends StatelessWidget {
  const DropdownWithAdd({
    super.key,
    this.fieldKey,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    required this.addTooltip,
    required this.onAdd,
    this.validator,
  });

  /// Key of the dropdown itself; changing it resets the field.
  final Key? fieldKey;
  final String? value;
  final String label;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final String addTooltip;
  final VoidCallback onAdd;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: fieldKey,
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: items,
          onChanged: onChanged,
          validator: validator,
        ),
      ),
      const SizedBox(width: 4),
      IconButton(
        tooltip: addTooltip,
        onPressed: onAdd,
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
    ],
  );
}

/// A dropdown item showing [text] on one line.
DropdownMenuItem<String> catalogItem(
  String value,
  String text, {
  bool enabled = true,
}) => DropdownMenuItem(
  value: value,
  enabled: enabled,
  child: Text(text, overflow: TextOverflow.ellipsis),
);

/// The method's tools as chips to mark the ones used, and a button to
/// manage them.
class MethodToolChips extends StatelessWidget {
  const MethodToolChips({
    super.key,
    required this.tools,
    required this.selected,
    required this.onToggle,
    required this.onManage,
    this.useCounts = const {},
  });

  final List<MethodTool> tools;
  final Set<String> selected;
  final void Function(String toolId, bool selected) onToggle;
  final VoidCallback onManage;
  final Map<String, int> useCounts;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final shown = [
      for (final tool in tools)
        if (tool.archivedAtMs == null || selected.contains(tool.id)) tool,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tool in shown)
                FilterChip(
                  tooltip: s.brewsCount(useCounts[tool.id] ?? 0),
                  label: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(tool.name),
                      // How often it was used, quieter than its name.
                      Text(
                        '${useCounts[tool.id] ?? 0}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  selected: selected.contains(tool.id),
                  onSelected: (on) => onToggle(tool.id, on),
                ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.tune_rounded),
            label: Text(s.manageMethodTools),
          ),
        ),
      ],
    );
  }
}

/// Says that the recipe was filled from the last brew with [methodName].
class MethodMemoryHint extends StatelessWidget {
  const MethodMemoryHint(this.methodName, {super.key, this.favorite = false});

  final String methodName;

  /// Whether the values came from the favourite recipe.
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          favorite ? Icons.favorite_rounded : Icons.history_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            favorite
                ? s.methodMemoryFavorite(methodName)
                : s.methodMemoryApplied(methodName),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class IntegerField extends StatelessWidget {
  const IntegerField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return null;
        final parsed = int.tryParse(text);
        return parsed == null || parsed <= 0 ? s.invalidNumber : null;
      },
    );
  }
}

/// "Item n · roast date · grams left" for choosing an inventory record.
String inventoryLotLabel(CoffeeLot lot, int itemNumber, AppLocalizations s) => [
  s.inventoryItem(itemNumber),
  if (lot.roastDate case final roastDate?)
    formatRegionalDate(DateTime.parse(roastDate), regionalLocale),
  if (lot.remainingGrams case final grams?)
    '${formatDecimal(grams, pattern: '0.#', locale: regionalLocale.toString())} g'
  else
    s.unknownStock,
].join(', ');
