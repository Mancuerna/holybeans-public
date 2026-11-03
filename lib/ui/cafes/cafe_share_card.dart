import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/ui/cafes/cafe_share_text.dart';
import 'package:holybeans/ui/core/journal_share_card.dart';

class CafeShareCard extends StatelessWidget {
  const CafeShareCard({
    super.key,
    required this.rows,
    required this.selected,
    this.photo,
  });

  final List<CafeShareRow> rows;
  final Set<String> selected;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    String? title;
    final sections = [<(String, String)>[], <(String, String)>[]];
    for (final row in rows) {
      if (!selected.contains(row.id)) continue;
      if (row.id == 'cafe') {
        title = row.value;
      } else {
        sections[row.personal ? 1 : 0].add((row.label, row.value));
      }
    }
    return JournalShareCard(
      key: const ValueKey('cafe-share-card-preview'),
      title: title,
      sections: sections.where((section) => section.isNotEmpty).toList(),
      photo: photo,
    );
  }
}
