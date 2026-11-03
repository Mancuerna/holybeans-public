import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/roaster_profile.dart';

typedef GroupedBean = ({
  String id,
  String roaster,
  double? grams,
  FreshnessPhase? phase,
});

class BeanRoasterGroup {
  BeanRoasterGroup(this.key, this.name, List<GroupedBean> beans)
    : beans = List.unmodifiable(beans);

  final String key;
  final String name;
  final List<GroupedBean> beans;

  double get knownGrams =>
      beans.fold(0, (sum, bean) => sum + (bean.grams ?? 0));
  bool get hasUnknownStock => beans.any((bean) => bean.grams == null);
  Map<FreshnessPhase, int> get phases => {
    for (final phase in FreshnessPhase.values)
      if (beans.any((bean) => bean.phase == phase))
        phase: beans.where((bean) => bean.phase == phase).length,
  };
}

List<BeanRoasterGroup> groupBeansByRoaster(List<GroupedBean> beans) {
  final groups = <String, List<GroupedBean>>{};
  for (final bean in beans) {
    (groups[roasterKey(bean.roaster)] ??= []).add(bean);
  }
  final keys = groups.keys.toList()
    ..sort(
      (a, b) => a.isEmpty
          ? 1
          : b.isEmpty
          ? -1
          : a.compareTo(b),
    );
  return [
    for (final key in keys)
      BeanRoasterGroup(
        key,
        roasterName(groups[key]!.first.roaster),
        groups[key]!,
      ),
  ];
}
