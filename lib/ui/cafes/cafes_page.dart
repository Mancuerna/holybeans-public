import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_stats.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_drink_form.dart';
import 'package:holybeans/ui/cafes/cafe_share_flow.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

class CafesPage extends StatefulWidget {
  const CafesPage({super.key, required this.repository, this.photos});
  final CafeRepository repository;
  final PhotoStore? photos;
  @override
  State<CafesPage> createState() => _CafesPageState();
}

class _CafesPageState extends State<CafesPage> {
  late final Stream<CafeJournalData> stream = widget.repository.watch();
  Future<void> edit(CafeJournalData data, [CafeDrink? drink]) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CafeDrinkForm(
            repository: widget.repository,
            data: data,
            existing: drink,
            photos: widget.photos,
          ),
        ),
      );
  Future<void> remove(CafeJournalData data, CafeDrink drink) async {
    final s = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.cafeDeleteTitle),
        content: Text(s.cafeDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.repository.delete(drink.id);
      for (final name in data.photosOf(drink.id)) {
        await widget.repository.deletePhotoIfUnused(widget.photos, name);
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(context, error, s.saveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return StreamBuilder<CafeJournalData>(
      stream: stream,
      builder: (context, snap) {
        final data = snap.data;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.cafeTitle),
              bottom: TabBar(
                tabs: [
                  Tab(
                    key: const ValueKey('cafe-history-tab'),
                    text: s.cafeHistoryTitle,
                  ),
                  Tab(
                    key: const ValueKey('cafe-stats-tab'),
                    text: s.statsTitle,
                  ),
                ],
              ),
            ),
            floatingActionButton: data == null
                ? null
                : FloatingActionButton.extended(
                    key: const ValueKey('cafe-add'),
                    onPressed: () => edit(data),
                    icon: const Icon(Icons.add),
                    label: Text(s.cafeAddDrink),
                  ),
            body: data == null
                ? Center(
                    child: snap.hasError
                        ? Text(s.cafeLoadFailed)
                        : const CircularProgressIndicator(),
                  )
                : TabBarView(
                    children: [
                      data.drinks.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(child: Text(s.cafeEmpty)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: data.drinks.length,
                              itemBuilder: (context, i) {
                                final d = data.drinks[i];
                                final c = data.cafeOf(d);
                                final detail =
                                    [
                                          data.roasterOf(d),
                                          d.coffeeName,
                                          d.originCountry,
                                          d.process,
                                        ]
                                        .whereType<String>()
                                        .where((v) => v.isNotEmpty)
                                        .join(' · ');
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  child: ListTile(
                                    onTap: () => edit(data, d),
                                    title: Text(
                                      '${c.name}\u00a0· ${d.drinkType}',
                                    ),
                                    subtitle: Text(
                                      [
                                        detail,
                                        [
                                          c.city,
                                          c.country,
                                        ].whereType<String>().join(' · '),
                                        formatRegionalDate(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            d.drankAtMs,
                                          ),
                                          regionalLocale,
                                        ),
                                        if (d.rating != null)
                                          '${s.rating}: ${formatDecimal(d.rating, pattern: '0.#', locale: Localizations.localeOf(context).toLanguageTag())}',
                                      ].where((v) => v.isNotEmpty).join('\n'),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          key: ValueKey('cafe-share-${d.id}'),
                                          tooltip: s.share,
                                          icon: const Icon(
                                            Icons.ios_share_rounded,
                                          ),
                                          onPressed: () => shareCafeDrinkFlow(
                                            context,
                                            data: data,
                                            drink: d,
                                            photos: widget.photos,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: s.delete,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: () => remove(data, d),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      _CafeStatsView(drinks: data.drinks),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CafeStatsView extends StatelessWidget {
  const _CafeStatsView({required this.drinks});
  final List<CafeDrink> drinks;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final stats = CafeStats(
      drinks.map(
        (d) => (
          cafeId: d.cafeId,
          rating: d.rating,
          priceCents: d.priceCents,
          currency: d.currency,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Text(s.cafeStatsHint),
        const SizedBox(height: 16),
        ListTile(
          title: Text(s.cafeDrinksLabel),
          trailing: Text('${stats.count}'),
        ),
        ListTile(
          title: Text(s.cafeVenuesLabel),
          trailing: Text('${stats.cafeCount}'),
        ),
        if (stats.averageRating != null)
          ListTile(
            title: Text(s.cafeAverageRating),
            trailing: Text(
              formatDecimal(
                stats.averageRating,
                pattern: '0.0',
                locale: Localizations.localeOf(context).toLanguageTag(),
              ),
            ),
          ),
        for (final entry in stats.spending.entries)
          ListTile(
            title: Text('${s.cafePriceTotal} · ${entry.key}'),
            trailing: Text(
              formatCafeCurrency(
                entry.value / 100,
                entry.key,
                Localizations.localeOf(context).toLanguageTag(),
              ),
            ),
          ),
      ],
    );
  }
}
