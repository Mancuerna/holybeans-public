part of 'app_database.dart';

extension RecipientMigration on AppDatabase {
  Future<void> mergeMigratedRecipients() async {
    final duplicates = await customSelect("""
      SELECT duplicate.id AS old_id, MIN(original.id) AS new_id
      FROM recipients duplicate JOIN recipients original
        ON original.name = duplicate.name
        AND original.empty_grams = duplicate.empty_grams
        AND original.archived_at_ms IS duplicate.archived_at_ms
        AND original.id < duplicate.id
      WHERE substr(duplicate.id, 1, 17) = 'method-recipient:'
        AND substr(original.id, 1, 17) = 'method-recipient:'
      GROUP BY duplicate.id
    """).get();
    for (final row in duplicates) {
      final oldId = row.read<String>('old_id');
      final newId = row.read<String>('new_id');
      await customStatement(
        'UPDATE brew_methods SET default_recipient_id = ? WHERE default_recipient_id = ?',
        [newId, oldId],
      );
      await customStatement(
        'UPDATE brews SET recipient_id = ? WHERE recipient_id = ?',
        [newId, oldId],
      );
      await customStatement('DELETE FROM recipients WHERE id = ?', [oldId]);
    }
  }
}

/// Brews saved before jugs had their own catalog (schema 31) kept only
/// their beverage weight: the form added the method's jug to show the
/// weight with jug. Schema 31 left them without a jug, so that field
/// vanished. This gives them back the jug they were weighed in:
///
/// - a brew imported from BeanConqueror, the jug that brew names there
///   (none if it names none);
/// - a brew made here, the jug its method had then.
///
/// Brews that have a jug, espresso brews and beverage weights stay as they
/// are. Run by the 32→33 migration and when restoring an older backup.
extension LegacyBrewRecipients on AppDatabase {
  Future<void> restoreLegacyBrewRecipients() async {
    final rows = await customSelect('''
      SELECT b.id, b.method_name, m.default_recipient_id, r.id AS record_id,
          p.raw_json
        FROM brews b
        JOIN brew_methods m ON m.id = b.method_id
        LEFT JOIN import_records r
          ON r.local_id = b.id AND r.source = 'beanconqueror' AND r.kind = 'brew'
        LEFT JOIN legacy_payloads p ON p.import_record_id = r.id
        WHERE b.recipient_id IS NULL
          AND COALESCE(m.category, '') <> 'espresso'
    ''').get();
    if (rows.isEmpty) return;
    final catalog = await select(recipients).get();
    final byId = {for (final r in catalog) r.id: r};
    for (final row in rows) {
      final Recipient? recipient;
      if (row.readNullable<String>('record_id') == null) {
        final methodJug = row.readNullable<String>('default_recipient_id');
        recipient = methodJug != null && methodJug.startsWith(_migratedPrefix)
            ? byId[methodJug]
            : null;
      } else {
        final Object? raw;
        try {
          raw = jsonDecode(row.readNullable<String>('raw_json') ?? '');
        } on FormatException {
          continue;
        }
        recipient = switch (bqBrewVessel(raw)) {
          final vessel? => await recipientFor(
            vessel.name ?? row.read<String>('method_name'),
            vessel.grams,
            catalog,
            preferredId: row.readNullable<String>('default_recipient_id'),
          ),
          null => null,
        };
      }
      if (recipient == null) continue;
      await customUpdate(
        'UPDATE brews SET recipient_id = ?, recipient_name = ?, '
        'recipient_grams = ? WHERE id = ?',
        variables: [
          Variable.withString(recipient.id),
          Variable.withString(recipient.name),
          Variable.withReal(recipient.emptyGrams),
          Variable.withString(row.read<String>('id')),
        ],
        updates: {brews},
      );
    }
  }

  static const _migratedPrefix = 'method-recipient:';

  /// The jug in [catalog] called [name] that weighs [grams], preferring
  /// [preferredId] and then jugs in use; added to the catalog (and to
  /// [catalog]) when there is none. Null for a weight no jug can have.
  Future<Recipient?> recipientFor(
    String name,
    double grams,
    List<Recipient> catalog, {
    String? preferredId,
  }) async {
    final label = name.trim().length > 120
        ? name.trim().substring(0, 120)
        : name.trim();
    if (label.isEmpty || !grams.isFinite || grams <= 0 || grams > 10000) {
      return null;
    }
    final matches =
        catalog
            .where(
              (r) =>
                  !r.isPortafilter && r.name == label && r.emptyGrams == grams,
            )
            .toList()
          ..sort((a, b) {
            int rank(Recipient r) => r.id == preferredId
                ? 0
                : r.archivedAtMs == null
                ? 1
                : 2;
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0 ? byRank : a.id.compareTo(b.id);
          });
    if (matches.isNotEmpty) return matches.first;
    final added = Recipient(
      isPortafilter: false,
      id: const Uuid().v4(),
      name: label,
      emptyGrams: grams,
    );
    await into(recipients).insert(added);
    catalog.add(added);
    return added;
  }
}
