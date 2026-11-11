/// Stable wire codes. Decode at boundaries; never persist enum ordinals.
enum RoastLevel {
  dark('dark'),
  medium('medium'),
  omni('omni'),
  light('light'),
  ultraLight('ultra_light');

  const RoastLevel(this.code);
  final String code;
  static RoastLevel? fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

enum MethodCategory {
  espresso('espresso'),
  pourover('pourover'),
  immersion('immersion');

  const MethodCategory(this.code);
  final String code;
  static MethodCategory? fromCode(String? code, {bool allowLegacy = false}) {
    if (allowLegacy && code == 'percolation') return pourover;
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

enum FrozenContainer {
  vacuumBag('vacuum_bag'),
  tube('tube'),
  zipBag('zip_bag'),
  jar('jar'),
  container('container'),
  originalBag('original_bag'),
  other('other');

  const FrozenContainer(this.code);
  final String code;
  static FrozenContainer? fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}
