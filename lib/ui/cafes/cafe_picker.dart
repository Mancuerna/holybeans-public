import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';

class CafePicker extends StatefulWidget {
  const CafePicker({super.key, required this.data});
  final CafeJournalData data;
  @override
  State<CafePicker> createState() => _CafePickerState();
}

class _CafePickerState extends State<CafePicker> {
  late final Future<List<CafeCatalogEntry>> catalog = CafeCatalog.load();
  String query = '';
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.cafeChooseVenue)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: s.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = foldSuggestion(v)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cafeManual),
          ),
          Expanded(
            child: FutureBuilder<List<CafeCatalogEntry>>(
              future: catalog,
              builder: (context, snap) {
                if (snap.hasError) {
                  reportError(
                    snap.error!,
                    snap.stackTrace ?? StackTrace.current,
                  );
                }
                final bySource = {
                  for (final entry in snap.data ?? <CafeCatalogEntry>[])
                    entry.venue.sourceKey: entry.venue,
                };
                final saved = widget.data.cafes
                    .map(
                      (c) => CafeInput(
                        id: c.id,
                        name: c.name,
                        city: c.city ?? bySource[c.sourceKey]?.city,
                        country: c.country ?? bySource[c.sourceKey]?.country,
                        address: c.address,
                        latitude: c.latitude,
                        longitude: c.longitude,
                        sourceKey: c.sourceKey,
                        sourceUrl: c.sourceUrl,
                      ),
                    )
                    .where(
                      (c) => foldSuggestion(
                        '${c.name} ${c.city ?? ''} ${c.country ?? ''}',
                      ).contains(query),
                    );
                final savedSources = {
                  for (final c in widget.data.cafes) c.sourceKey,
                };
                final suggested = (snap.data ?? <CafeCatalogEntry>[])
                    .where((c) => !savedSources.contains(c.venue.sourceKey))
                    .where(
                      (c) => foldSuggestion(
                        '${c.venue.name} ${c.venue.city ?? ''} ${c.venue.country ?? ''} ${c.category}',
                      ).contains(query),
                    )
                    .take(60);
                return ListView(
                  children: [
                    if (saved.isNotEmpty)
                      ListTile(title: Text(s.cafeSavedVenues)),
                    for (final c in saved)
                      ListTile(
                        title: Text(c.name),
                        subtitle: Text(
                          [c.city, c.country].whereType<String>().join(' · '),
                        ),
                        onTap: () => Navigator.pop(context, c),
                      ),
                    ListTile(
                      title: Text(s.cafeMapCatalog),
                      subtitle: Text(s.cafeCatalogSource),
                    ),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator()),
                    if (snap.hasError) ListTile(title: Text(s.cafeLoadFailed)),
                    for (final c in suggested)
                      ListTile(
                        title: Text(c.venue.name),
                        subtitle: Text(
                          [c.venue.city, c.venue.country, c.category]
                              .whereType<String>()
                              .where((v) => v.isNotEmpty)
                              .join(' · '),
                        ),
                        onTap: () => Navigator.pop(context, c.venue),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
