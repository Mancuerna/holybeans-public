import 'package:holybeans/domain/text_suggestions.dart';

// Experimental implementation for measurement only. Production keeps using
// foldSuggestion until its full search semantics are reviewed separately.
const _from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _to = 'aaaaaeeeeiiiiooooouuuunc';
final _accents = RegExp('[$_from]');
final _combining = RegExp(r'[\u0300-\u036f]');
final _whitespace = RegExp(r'\s+');

String foldWithoutCharacterList(String text) => text
    .trim()
    .toLowerCase()
    .replaceAllMapped(_accents, (match) => _to[_from.indexOf(match[0]!)])
    .replaceAll(_combining, '')
    .replaceAll(_whitespace, ' ');

bool metadataFirstMatches(String prefix, String? notes, String foldedQuery) =>
    foldSuggestion(prefix).contains(foldedQuery) ||
    foldSuggestion('$prefix ${notes ?? ''}').contains(foldedQuery);
