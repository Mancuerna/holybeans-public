/// Trims each comma-separated note, drops empty and repeated ones
/// (case-insensitively) and joins them with ", "; null when none is left.
String? normalizeFlavorNotes(String? source) {
  if (source == null) return null;
  final seen = <String>{};
  final notes = [
    for (final part in source.split(','))
      if (part.trim() case final note
          when note.isNotEmpty && seen.add(note.toLowerCase()))
        note,
  ];
  return notes.isEmpty ? null : notes.join(', ');
}
