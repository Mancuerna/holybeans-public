import 'package:flutter/material.dart';
import 'package:holybeans/domain/flavor_descriptors.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/flavor_note_chip.dart';
import 'package:holybeans/ui/core/flavor_note_labels.dart';

/// Chip editor backed by the existing comma-separated profile controller.
/// Opening the field or changing locale never rewrites its stored text.
class FlavorNotesField extends StatefulWidget {
  const FlavorNotesField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<FlavorNotesField> createState() => _FlavorNotesFieldState();
}

class _FlavorNotesFieldState extends State<FlavorNotesField> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  late List<String> _notes;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _notes = splitFlavorNotes(widget.controller.text);
    widget.controller.addListener(_readProfile);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(FlavorNotesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_readProfile);
      widget.controller.addListener(_readProfile);
      _notes = splitFlavorNotes(widget.controller.text);
      _input.clear();
    }
  }

  void _readProfile() {
    if (_writing) return;
    setState(() {
      _notes = splitFlavorNotes(widget.controller.text);
      _input.clear();
    });
  }

  void _focusChanged() => setState(() {});

  String _newNote(String value) =>
      flavorNoteLabel(value.trim(), AppLocalizations.of(context)!);

  void _writeProfile() {
    // Include the unfinished note so Save and the exit guard see it immediately.
    final all = appendFlavorNote(_notes, _newNote(_input.text));
    _writing = true;
    widget.controller.text = all.join(', ');
    _writing = false;
  }

  void _changed(String value) {
    // Let the keyboard finish an IME composition before splitting it.
    if (_input.value.composing.isValid && !_input.value.composing.isCollapsed) {
      _writeProfile();
      return;
    }
    setState(() {
      final parts = value.split(',');
      if (parts.length > 1) {
        for (final part in parts.take(parts.length - 1)) {
          _notes = appendFlavorNote(_notes, _newNote(part));
        }
        _input.value = TextEditingValue(
          text: parts.last,
          selection: TextSelection.collapsed(offset: parts.last.length),
        );
      }
      _writeProfile();
    });
  }

  void _commit(String note) {
    setState(() {
      _notes = appendFlavorNote(_notes, _newNote(note));
      _input.clear();
      _writeProfile();
    });
    _focus.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_readProfile);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final suggestions = _focus.hasFocus
        ? suggestFlavorNotes(_input.text, _notes)
        : const <FlavorDescriptor>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          isFocused: _focus.hasFocus,
          isEmpty: _notes.isEmpty && _input.text.isEmpty,
          decoration: InputDecoration(
            labelText: s.flavorProfile,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            helperText: s.flavorProfileHint,
            helperMaxLines: 3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_notes.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (index, note) in _notes.indexed)
                      FlavorNoteChip(
                        note: note,
                        onDeleted: () => setState(() {
                          _notes.removeAt(index);
                          _writeProfile();
                        }),
                      ),
                  ],
                ),
              TextFormField(
                key: const ValueKey('coffee-flavor-profile'),
                controller: _input,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: s.flavorNoteInputHint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: _changed,
                onFieldSubmitted: _commit,
                onEditingComplete: () {},
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.flavorNoteSuggestions,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final descriptor in suggestions)
                      ActionChip(
                        avatar: Icon(
                          Icons.add,
                          size: 16,
                          color: flavorNoteColor(descriptor.tone),
                        ),
                        label: Text(descriptor.label(s)),
                        onPressed: () => _commit(descriptor.label(s)),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
