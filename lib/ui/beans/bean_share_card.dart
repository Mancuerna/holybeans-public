import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/ui/beans/bean_share_text.dart';
import 'package:holybeans/ui/core/journal_share_card.dart';

class BeanShareCard extends StatelessWidget {
  const BeanShareCard({
    super.key,
    required this.rows,
    required this.selected,
    this.photo,
  });

  final List<BeanShareRow> rows;
  final Set<String> selected;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    String? title;
    final groups = <String, List<(String, String)>>{};
    for (final row in rows) {
      if (!selected.contains(row.id)) continue;
      if (row.id == 'name') {
        title = row.value;
        continue;
      }
      final group = row.personal
          ? 'personal'
          : row.id.contains('-')
          ? row.id.split('-').first
          : 'coffee';
      groups.putIfAbsent(group, () => []).add((row.label, row.value));
    }
    return JournalShareCard(
      key: const ValueKey('bean-share-card-preview'),
      title: title,
      sections: groups.values.toList(),
      photo: photo,
    );
  }
}
