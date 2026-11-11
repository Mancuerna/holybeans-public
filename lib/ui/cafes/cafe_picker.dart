import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class CafePicker extends StatefulWidget {
  const CafePicker({super.key, required this.data});
  final CafeJournalData data;
  @override
  State<CafePicker> createState() => _CafePickerState();
}

class _CafePickerState extends State<CafePicker> {
  late final Future<List<CafeCatalogEntry>> catalog = CafeCatalog.load();
  List<Cafe> _indexedCafes = const [];
  List<CafeCatalogEntry>? _indexedCatalog;
  List<_Choice> _saved = const [];
  List<_Choice> _suggested = const [];
  bool _dirty = true;
  String query = '';

  @override
  void didUpdateWidget(CafePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_indexedCafes, widget.data.cafes)) _dirty = true;
  }

  void _prepare(List<CafeCatalogEntry>? entries) {
    if (!_dirty && identical(entries, _indexedCatalog)) return;
    _dirty = false;
    _indexedCatalog = entries;
    _indexedCafes = List.of(widget.data.cafes);
    final bySource = {
      for (final entry in entries ?? <CafeCatalogEntry>[])
        entry.venue.sourceKey: entry.venue,
    };
    _saved = [
      for (final c in _indexedCafes)
        _choice(
          CafeInput(
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
        ),
    ];
    final savedSources = {for (final c in _indexedCafes) c.sourceKey};
    _suggested = [
      for (final c in entries ?? <CafeCatalogEntry>[])
        if (!savedSources.contains(c.venue.sourceKey))
          _choice(c.venue, c.category),
    ];
  }

  Widget _tile(_Choice choice) {
    final c = choice.venue;
    final category = choice.category;
    final location = [c.city, c.country].whereType<String>();
    return ListTile(
      title: Text(c.name),
      subtitle: Text(
        category == null
            ? location.join(' · ')
            : [...location, category].where((v) => v.isNotEmpty).join(' · '),
      ),
      onTap: () => Navigator.pop(context, c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
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
                _prepare(snap.data);
                final saved = _saved
                    .where((c) => c.search.contains(query))
                    .toList();
                final suggested = _suggested
                    .where((c) => c.search.contains(query))
                    .take(60)
                    .toList();
                final headers = [
                  ListTile(
                    title: Text(s.cafeMapCatalog),
                    subtitle: Text(s.cafeCatalogSource),
                  ),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator()),
                  if (snap.hasError) ListTile(title: Text(s.cafeLoadFailed)),
                ];
                return ListView.builder(
                  itemCount:
                      saved.length +
                      (saved.isEmpty ? 0 : 1) +
                      headers.length +
                      suggested.length,
                  itemBuilder: (context, index) {
                    if (saved.isNotEmpty) {
                      if (index == 0) {
                        return ListTile(title: Text(s.cafeSavedVenues));
                      }
                      index--;
                      if (index < saved.length) return _tile(saved[index]);
                      index -= saved.length;
                    }
                    if (index < headers.length) return headers[index];
                    return _tile(suggested[index - headers.length]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Choice = ({CafeInput venue, String? category, String search});

_Choice _choice(CafeInput venue, [String? category]) => (
  venue: venue,
  category: category,
  search: foldSuggestion(
    '${venue.name} ${venue.city ?? ''} ${venue.country ?? ''}${category == null ? '' : ' $category'}',
  ),
);
