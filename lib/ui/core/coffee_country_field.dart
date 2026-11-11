import 'package:flutter/material.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// The country, suggested by name in the app's language and shown with its
/// flag.
class CoffeeCountryField extends StatelessWidget {
  const CoffeeCountryField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.label,
    this.fieldKey = const ValueKey('origin-country'),
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onChanged;
  final String? label;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, _, _) => RawAutocomplete<CoffeeCountry>(
        textEditingController: controller,
        focusNode: focusNode,
        displayStringForOption: (country) => country.nameFor(s.localeName),
        optionsBuilder: (value) {
          final query = foldCountryName(value.text);
          if (query.isEmpty) return const [];
          return coffeeCountries
              .where(
                (country) =>
                    foldCountryName(country.nameFor(s.localeName))
                        .startsWith(query) &&
                    foldCountryName(country.nameFor(s.localeName)) != query,
              )
              .take(5);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
            TextFormField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: label ?? s.country,
                prefixText: switch (coffeeCountryFor(controller.text)) {
                  final country? => '${country.flag}  ',
                  null => null,
                },
              ),
              onChanged: (_) => onChanged?.call(),
            ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final country in options)
                    ListTile(
                      key: ValueKey('country-option-${country.code}'),
                      leading: ExcludeSemantics(
                        child: Text(
                          country.flag,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      title: Text(country.nameFor(s.localeName)),
                      onTap: () => onSelected(country),
                    ),
                ],
              ),
            ),
          ),
        ),
        onSelected: (country) {
          if (country.code == 'BR') const DeviceFeedback().faaah();
          onChanged?.call();
        },
      ),
    );
  }
}
