import 'dart:typed_data';

import 'package:holybeans/domain/text_folding.dart';

/// Lowercase, accent-free text for matching suggestions without rewriting data.
String foldSuggestion(String text) {
  final lower = text.trim().toLowerCase();
  final buffer = Uint16List(lower.length);
  var length = 0;
  var space = false;
  for (var i = 0; i < lower.length; i++) {
    final code = lower.codeUnitAt(i);
    if (code >= 0x0300 && code <= 0x036f) continue;
    if (_whiteSpace(code)) {
      if (!space) buffer[length++] = 32;
      space = true;
      continue;
    }
    space = false;
    buffer[length++] = foldLatinAccent(code);
  }
  return String.fromCharCodes(buffer, 0, length);
}

/// Substring matching with [foldSuggestion]'s exact normalization, stopping at
/// the first match without allocating a complete normalized copy of each note.
/// The constructor's query must already be folded. Prefix fallback keeps misses
/// linear even for patterns such as `aaaaab` in a long repeated note.
class FoldedTextMatcher {
  FoldedTextMatcher(String foldedQuery)
    : _query = foldedQuery.codeUnits,
      _fallback = List.filled(foldedQuery.length, 0) {
    var matched = 0;
    for (var i = 1; i < _query.length; i++) {
      while (matched > 0 && _query[i] != _query[matched]) {
        matched = _fallback[matched - 1];
      }
      if (_query[i] == _query[matched]) matched++;
      _fallback[i] = matched;
    }
  }

  final List<int> _query;
  final List<int> _fallback;

  bool matches(String text) {
    if (_query.isEmpty) return true;
    final lower = text.trim().toLowerCase();
    var matched = 0;
    var space = false;
    for (var i = 0; i < lower.length; i++) {
      var code = lower.codeUnitAt(i);
      if (code >= 0x0300 && code <= 0x036f) continue;
      if (_whiteSpace(code)) {
        if (space) continue;
        space = true;
        code = 32;
      } else {
        space = false;
        code = foldLatinAccent(code);
      }
      while (matched > 0 && code != _query[matched]) {
        matched = _fallback[matched - 1];
      }
      if (code == _query[matched]) matched++;
      if (matched == _query.length) return true;
    }
    return false;
  }
}

// ECMAScript RegExp \s, matching the original folding contract. trim() above
// deliberately precedes removing combining marks, including at the boundaries.
bool _whiteSpace(int code) =>
    (code >= 9 && code <= 13) ||
    code == 32 ||
    code == 0xa0 ||
    code == 0x1680 ||
    (code >= 0x2000 && code <= 0x200a) ||
    code == 0x2028 ||
    code == 0x2029 ||
    code == 0x202f ||
    code == 0x205f ||
    code == 0x3000 ||
    code == 0xfeff;

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
