/// How the Beans list is sorted.
enum BeanSort { name, recentBrew, roastDate, freshness, frozenDate }

/// How the Beans and Brews lists are shown: kept between launches so the
/// user does not pick the same order every time.
class ListOptions {
  const ListOptions({
    this.beanSort = BeanSort.name,
    this.frozenBeanSort = BeanSort.frozenDate,
    this.frozenBeansAscending = true,
    this.beansAscending = true,
    this.favoritesFirst = true,
    this.beansCompact = false,
    this.beansByRoaster = false,
    this.archivedBeansCompact = true,
    this.archivedBeanSort = BeanSort.recentBrew,
    this.archivedBeansAscending = false,
    this.brewsAscending = false,
    this.brewsCompact = false,
    this.showArchivedBrews = false,
  });

  /// Options saved by [toJson]; anything missing or unreadable keeps its
  /// default, so older and newer apps can share the value.
  factory ListOptions.fromJson(Object? json) {
    if (json is! Map) return const ListOptions();
    bool flag(String key, bool fallback) => switch (json[key]) {
      final bool value => value,
      _ => fallback,
    };
    const defaults = ListOptions();
    return ListOptions(
      beanSort:
          BeanSort.values
              .where((sort) => sort.name == json['beanSort'])
              .firstOrNull ??
          defaults.beanSort,
      frozenBeanSort:
          BeanSort.values
              .where(
                (sort) =>
                    sort.name == json['frozenBeanSort'] &&
                    sort != BeanSort.freshness,
              )
              .firstOrNull ??
          defaults.frozenBeanSort,
      frozenBeansAscending: flag(
        'frozenBeansAscending',
        defaults.frozenBeansAscending,
      ),
      beansAscending: flag('beansAscending', defaults.beansAscending),
      favoritesFirst: flag('favoritesFirst', defaults.favoritesFirst),
      beansCompact: flag('beansCompact', defaults.beansCompact),
      beansByRoaster: flag('beansByRoaster', defaults.beansByRoaster),
      archivedBeansCompact: flag(
        'archivedBeansCompact',
        defaults.archivedBeansCompact,
      ),
      archivedBeanSort:
          BeanSort.values
              .where((sort) => sort.name == json['archivedBeanSort'])
              .firstOrNull ??
          defaults.archivedBeanSort,
      archivedBeansAscending: flag(
        'archivedBeansAscending',
        defaults.archivedBeansAscending,
      ),
      brewsAscending: flag('brewsAscending', defaults.brewsAscending),
      brewsCompact: flag('brewsCompact', defaults.brewsCompact),
      showArchivedBrews: flag('showArchivedBrews', defaults.showArchivedBrews),
    );
  }

  final BeanSort beanSort;
  final BeanSort frozenBeanSort;
  final bool frozenBeansAscending;
  final bool beansAscending;
  final bool favoritesFirst;
  final bool beansCompact;
  final bool beansByRoaster;

  /// Density of the Archived beans tab, apart from the others: hundreds of
  /// finished bags are looked up, not browsed, so they start compact.
  final bool archivedBeansCompact;

  /// Sort of the Archived tab, apart from the others: the bags finished
  /// last are the ones looked for, so it starts with the latest brewed.
  final BeanSort archivedBeanSort;
  final bool archivedBeansAscending;
  final bool brewsAscending;
  final bool brewsCompact;
  final bool showArchivedBrews;

  Map<String, Object> toJson() => {
    'beanSort': beanSort.name,
    'frozenBeanSort': frozenBeanSort.name,
    'frozenBeansAscending': frozenBeansAscending,
    'beansAscending': beansAscending,
    'favoritesFirst': favoritesFirst,
    'beansCompact': beansCompact,
    'beansByRoaster': beansByRoaster,
    'archivedBeansCompact': archivedBeansCompact,
    'archivedBeanSort': archivedBeanSort.name,
    'archivedBeansAscending': archivedBeansAscending,
    'brewsAscending': brewsAscending,
    'brewsCompact': brewsCompact,
    'showArchivedBrews': showArchivedBrews,
  };

  ListOptions copyWith({
    BeanSort? beanSort,
    BeanSort? frozenBeanSort,
    bool? frozenBeansAscending,
    bool? beansAscending,
    bool? favoritesFirst,
    bool? beansCompact,
    bool? beansByRoaster,
    bool? archivedBeansCompact,
    BeanSort? archivedBeanSort,
    bool? archivedBeansAscending,
    bool? brewsAscending,
    bool? brewsCompact,
    bool? showArchivedBrews,
  }) => ListOptions(
    beanSort: beanSort ?? this.beanSort,
    frozenBeanSort: frozenBeanSort ?? this.frozenBeanSort,
    frozenBeansAscending: frozenBeansAscending ?? this.frozenBeansAscending,
    beansAscending: beansAscending ?? this.beansAscending,
    favoritesFirst: favoritesFirst ?? this.favoritesFirst,
    beansCompact: beansCompact ?? this.beansCompact,
    beansByRoaster: beansByRoaster ?? this.beansByRoaster,
    archivedBeansCompact: archivedBeansCompact ?? this.archivedBeansCompact,
    archivedBeanSort: archivedBeanSort ?? this.archivedBeanSort,
    archivedBeansAscending:
        archivedBeansAscending ?? this.archivedBeansAscending,
    brewsAscending: brewsAscending ?? this.brewsAscending,
    brewsCompact: brewsCompact ?? this.brewsCompact,
    showArchivedBrews: showArchivedBrews ?? this.showArchivedBrews,
  );
}
