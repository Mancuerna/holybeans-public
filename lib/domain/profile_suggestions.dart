import 'package:holybeans/domain/text_suggestions.dart';

typedef ProfileUse = ({String name, String? methodId, int brewedAtMs});

class ProfileSuggestions {
  ProfileSuggestions(Iterable<ProfileUse> uses)
    : _uses = uses.toList()
        ..sort((a, b) {
          final recent = b.brewedAtMs.compareTo(a.brewedAtMs);
          return recent != 0 ? recent : a.name.compareTo(b.name);
        });

  final List<ProfileUse> _uses;
  final Map<String?, List<String>> _byMethod = {};

  List<String> forMethod(String? methodId) =>
      _byMethod.putIfAbsent(methodId, () {
        final names = <String, String>{};
        void add(ProfileUse use) {
          final name = use.name.trim();
          final folded = foldSuggestion(name);
          if (folded.isNotEmpty) names.putIfAbsent(folded, () => name);
        }

        if (methodId != null) {
          for (final use in _uses) {
            if (use.methodId == methodId) add(use);
          }
        }
        for (final use in _uses) {
          add(use);
        }
        return List.unmodifiable(names.values);
      });
}
