enum FrozenStockState { none, some, all }

FrozenStockState frozenStockState(double? available, double frozen) {
  if (frozen <= 0) return FrozenStockState.none;
  return available != null && available < 0.05
      ? FrozenStockState.all
      : FrozenStockState.some;
}
