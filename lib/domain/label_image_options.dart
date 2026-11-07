enum LabelImagePosition { top, left, right }

enum LabelImageAlignment { start, center, end }

enum LabelImageMode { logo, photo }

class LabelImageOptions {
  const LabelImageOptions({
    this.position = LabelImagePosition.top,
    this.alignment = LabelImageAlignment.center,
    this.size = 0.4,
    this.mode = LabelImageMode.logo,
    this.contrast = 1,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  final LabelImagePosition position;
  final LabelImageAlignment alignment;
  final double size;
  final LabelImageMode mode;
  final double contrast;
  final double offsetX;
  final double offsetY;

  void validate() {
    if (!size.isFinite ||
        size < 0.1 ||
        size > 1 ||
        !contrast.isFinite ||
        contrast < 0.5 ||
        contrast > 2 ||
        !offsetX.isFinite ||
        offsetX.abs() > 1 ||
        !offsetY.isFinite ||
        offsetY.abs() > 1) {
      throw const FormatException('Invalid label image options');
    }
  }

  LabelImageOptions copyWith({
    LabelImagePosition? position,
    LabelImageAlignment? alignment,
    double? size,
    LabelImageMode? mode,
    double? contrast,
    double? offsetX,
    double? offsetY,
  }) => LabelImageOptions(
    position: position ?? this.position,
    alignment: alignment ?? this.alignment,
    size: size ?? this.size,
    mode: mode ?? this.mode,
    contrast: contrast ?? this.contrast,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
  );

  Map<String, Object> toJson() => {
    'position': position.name,
    'alignment': alignment.name,
    'size': size,
    'mode': mode.name,
    'contrast': contrast,
    'offsetX': offsetX,
    'offsetY': offsetY,
  };

  static LabelImageOptions fromJson(Map<String, dynamic> json) {
    final result = LabelImageOptions(
      position: LabelImagePosition.values.byName(json['position'] as String),
      alignment: LabelImageAlignment.values.byName(json['alignment'] as String),
      size: (json['size'] as num).toDouble(),
      mode: LabelImageMode.values.byName(json['mode'] as String),
      contrast: (json['contrast'] as num).toDouble(),
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is LabelImageOptions &&
      position == other.position &&
      alignment == other.alignment &&
      size == other.size &&
      mode == other.mode &&
      contrast == other.contrast &&
      offsetX == other.offsetX &&
      offsetY == other.offsetY;
  @override
  int get hashCode =>
      Object.hash(position, alignment, size, mode, contrast, offsetX, offsetY);
}
