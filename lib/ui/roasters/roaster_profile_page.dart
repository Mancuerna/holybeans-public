import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class RoasterProfilePage extends StatelessWidget {
  const RoasterProfilePage({
    super.key,
    required this.name,
    required this.profile,
    required this.onOpenCoffee,
  });
  final String name;
  final RoasterProfile? profile;
  final ValueChanged<String> onOpenCoffee;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final p = profile;
    final number = NumberFormat.decimalPattern(regionalLocale.toString());
    String n(num value) => number.format(value);
    String? coverage(int known) => p == null || known == p.coffees.length
        ? null
        : s.roasterCoverage(known, p.coffees.length);
    String rating(double? value) => value == null
        ? '—'
        : '${NumberFormat('0.#', regionalLocale.toString()).format(value)} / 10';
    final countries = [
      for (final country
          in p?.countries.entries ?? const <MapEntry<String, String>>[])
        coffeeCountryFor(country.key)?.nameFor(s.localeName) ?? country.value,
    ]..sort();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(16) > 22
            ? 112
            : 64,
        title: Text(
          p?.name ?? roasterName(name),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: p == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.roasterUnavailable),
              ),
            )
          : SafeArea(
              child: CustomScrollView(
                key: ValueKey('roaster-profile-${p.key}'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.roasterHistoryHint,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (p.cafeDrinks.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              '${s.cafeDrinksLabel}: ${p.cafeDrinks.length}',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (p.cafeRating != null)
                              Text(
                                '${s.cafeAverageRating}: ${rating(p.cafeRating)}',
                              ),
                            for (final drink in p.cafeDrinks)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${drink.cafe} · ${drink.drinkType}',
                                ),
                                subtitle: drink.origin == null
                                    ? null
                                    : Text(drink.origin!),
                              ),
                          ],
                          const SizedBox(height: 22),
                          // Only figures there is data for; coverage shows
                          // when part of the coffees lack it.
                          StatGrid(
                            items: [
                              if (p.brewsByCoffee.length == p.coffees.length)
                                StatItem(
                                  s.roasterCoffeesTile,
                                  n(p.coffees.length),
                                )
                              else ...[
                                StatItem(
                                  s.roasterCoffeeCount,
                                  n(p.coffees.length),
                                ),
                                StatItem(
                                  s.roasterPreparedCoffees,
                                  n(p.brewsByCoffee.length),
                                ),
                              ],
                              StatItem(s.statsBrews, n(p.brewCount)),
                              if (p.weighedCoffees > 0)
                                StatItem(
                                  s.roasterPurchasedWeight,
                                  formatGrams(
                                    p.purchasedGrams,
                                    regionalLocale.toString(),
                                  ),
                                  caption: coverage(p.weighedCoffees),
                                ),
                              if (p.pricedCoffees > 0)
                                StatItem(
                                  s.roasterTotalSpent,
                                  formatEuro(
                                    p.spentCents / 100,
                                    regionalLocale.toString(),
                                  ),
                                  caption: coverage(p.pricedCoffees),
                                ),
                              if (p.coffeeRating != null)
                                StatItem(
                                  s.roasterCoffeeRating,
                                  rating(p.coffeeRating),
                                  caption: s.roasterRatedCoffees(
                                    p.coffeeRatingCount,
                                  ),
                                ),
                              if (p.brewRating != null)
                                StatItem(
                                  s.roasterBrewRating,
                                  rating(p.brewRating),
                                  caption: s.roasterRatedBrews(
                                    p.brewRatingCount,
                                  ),
                                ),
                              if (p.lastPurchase case final date?)
                                StatItem(
                                  s.roasterLatestPurchase,
                                  formatRegionalDate(date, regionalLocale),
                                  caption: coverage(p.datedCoffees),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            s.roasterDataHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            s.roasterOrigins,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          if (countries.isEmpty)
                            Text(s.roasterNoOrigins)
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final country in countries)
                                  Chip(label: Text(country)),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            s.roasterOriginCoverage(
                              p.coffeesWithOrigin,
                              p.brewsByCoffee.length,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            s.roasterCoffees,
                            style: theme.textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: p.coffees.length,
                    itemBuilder: (context, index) {
                      final coffee = p.coffees[index];
                      return ListTile(
                        key: ValueKey('roaster-coffee-${coffee.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        title: Text(coffee.name),
                        subtitle: Text(
                          [
                            if (coffee.archived) s.archivedStatus,
                            s.brewsCount(p.brewsByCoffee[coffee.id] ?? 0),
                          ].join(', '),
                        ),
                        leading: Icon(
                          coffee.archived
                              ? Icons.inventory_2_outlined
                              : Icons.coffee_outlined,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => onOpenCoffee(coffee.id),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }
}
