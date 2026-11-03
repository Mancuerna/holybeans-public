/// Lowercase, accent-free text for matching suggestions without rewriting data.
String foldSuggestion(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Existing spellings, trimmed, deduplicated for display and sorted by name.
List<String> uniqueSuggestions(Iterable<String?> values) {
  final byName = <String, String>{};
  for (final value in values) {
    if (value == null) continue;
    final name = value.trim();
    final folded = foldSuggestion(name);
    if (folded.isNotEmpty) byName.putIfAbsent(folded, () => name);
  }
  return byName.values.toList()
    ..sort((a, b) => foldSuggestion(a).compareTo(foldSuggestion(b)));
}
