import 'package:flutter/material.dart';
import 'package:holybeans/domain/text_suggestions.dart';

/// A free-text field that can reuse a spelling already in the journal.
class SuggestedTextField extends StatefulWidget {
  const SuggestedTextField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.suggestions,
    this.maxLength,
    this.validator,
    this.textCapitalization = TextCapitalization.words,
    this.fieldKey,
    this.suggestionsAbove = false,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final List<String> suggestions;
  final int? maxLength;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;
  final Key? fieldKey;
  final bool suggestionsAbove;

  @override
  State<SuggestedTextField> createState() => _SuggestedTextFieldState();
}

class _SuggestedTextFieldState extends State<SuggestedTextField> {
  final focus = FocusNode();

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: focus,
    optionsViewOpenDirection: widget.suggestionsAbove
        ? OptionsViewOpenDirection.up
        : OptionsViewOpenDirection.down,
    optionsBuilder: (value) {
      final query = foldSuggestion(value.text);
      if (query.isEmpty) return const [];
      return widget.suggestions
          .where((option) {
            final name = foldSuggestion(option);
            return name.startsWith(query) && name != query;
          })
          .take(5);
    },
    fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
        TextFormField(
          key: widget.fieldKey,
          controller: controller,
          focusNode: focusNode,
          decoration: widget.decoration,
          maxLength: widget.maxLength,
          validator: widget.validator,
          textCapitalization: widget.textCapitalization,
          onFieldSubmitted: (_) => onSubmit(),
        ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: widget.suggestionsAbove
          ? AlignmentDirectional.bottomStart
          : AlignmentDirectional.topStart,
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
              for (final (index, option) in options.indexed)
                ListTile(
                  selected: AutocompleteHighlightedOption.of(context) == index,
                  title: Text(option),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
