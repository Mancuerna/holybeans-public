import 'package:holybeans/domain/marklife_protocol.dart';

enum LabelPrinterModel {
  d110('D110', 96, 203, 2),
  b1('B1', 384, 203, 3),
  b1Pro('B1 Pro', 576, 300, 3),
  b21('B21', 384, 203, 3),
  b2('B2', 384, 203, 3),
  b2Pro('B2 Pro', 576, 300, 3),
  d11('D11', 96, 203, 2),
  d11H('D11-H', 144, 300, 3),
  marklifeP12('P12', 96, 203, 2);

  const LabelPrinterModel(
    this.label,
    this.headPixels,
    this.dpi,
    this.defaultDensity,
  );
  final String label;
  final int headPixels;
  final int dpi;
  final int defaultDensity;

  // Keep the already verified 203 dpi geometry exactly as delivered.
  double get pixelsPerMm => dpi == 203 ? 8 : dpi / 25.4;
  bool get isNiimbot => this != marklifeP12;
  String get displayName =>
      isNiimbot ? 'Niimbot $label' : 'Pristar / Marklife P12';
  bool get continuousTape => this == marklifeP12;
  bool get supportsImages => true;
  bool get rotateForFeed =>
      this == d110 || this == d11 || this == d11H || this == marklifeP12;
  bool get needsProtocolVersion =>
      this == b1Pro || this == b2 || this == b2Pro || this == d11H;
  bool acceptsId(int id) => switch (this) {
    marklifeP12 => false,
    d110 => id == 2304 || id == 2305,
    d11 => id == 512,
    d11H => id == 528,
    b1 => id == 4096,
    b1Pro => id == 4097,
    b21 => const [768, 769, 771, 775, 776, 777].contains(id),
    b2 => id == 6913,
    b2Pro => id == 6912,
  };
  bool matchesName(String? name) {
    if (this == marklifeP12) return MarklifeProtocol.matchesName(name);
    if (name == null) return false;
    final pattern = switch (this) {
      marklifeP12 => throw StateError('Handled by Marklife protocol'),
      d110 => r'^D110(?:-|$)',
      d11 => r'^D11(?:-|$)',
      d11H => r'^D11(?:[_ -]?H)?(?:-|$)',
      b1 => r'^B1(?:-|$)',
      // Pro units can advertise the same prefix as the base model. Identity
      // from the printer is mandatory; a name never authorizes printing.
      b1Pro => r'^B1(?:(?:[ _]?Pro)?(?:-|$))',
      b21 => r'^B21(?:S)?(?:[_ -](?:C2B|L2B))?(?:-|$)',
      b2 => r'^B2(?:-|$)',
      b2Pro => r'^B2(?:(?:[ _]?Pro)?(?:-|$))',
    };
    return RegExp(pattern, caseSensitive: false).hasMatch(name);
  }

  List<LabelPaper> get papers => continuousTape
      ? [
          for (final length in MarklifeProtocol.lengthsMm)
            LabelPaper(15, length, this),
        ]
      : rotateForFeed
      ? [
          for (final (width, length) in const [
            (15, 30),
            (12, 40),
            (15, 40),
            (15, 50),
          ])
            LabelPaper(width, length, this),
        ]
      : [
          for (final (width, length) in const [
            (30, 20),
            (40, 30),
            (40, 40),
            (50, 30),
            (50, 50),
            (50, 80),
          ])
            LabelPaper(width, length, this),
        ];
  LabelPaper get defaultPaper => continuousTape
      ? LabelPaper(15, 40, this)
      : rotateForFeed
      ? LabelPaper(15, 30, this)
      : LabelPaper(50, 30, this);
}

class LabelPaper {
  const LabelPaper(
    this.widthMm,
    this.lengthMm, [
    this.model = LabelPrinterModel.d110,
  ]);
  static const mm15x30 = LabelPaper(15, 30);
  static const mm12x40 = LabelPaper(12, 40);
  static const mm15x40 = LabelPaper(15, 40);
  static const mm15x50 = LabelPaper(15, 50);
  static const mm30x20 = LabelPaper(30, 20, LabelPrinterModel.b1);
  static const mm40x30 = LabelPaper(40, 30, LabelPrinterModel.b1);
  static const mm40x40 = LabelPaper(40, 40, LabelPrinterModel.b1);
  static const mm50x30 = LabelPaper(50, 30, LabelPrinterModel.b1);
  static const mm50x50 = LabelPaper(50, 50, LabelPrinterModel.b1);
  static const mm50x80 = LabelPaper(50, 80, LabelPrinterModel.b1);

  final int widthMm;
  final int lengthMm;
  final LabelPrinterModel model;
  int get crossFeedPixels =>
      (widthMm * model.pixelsPerMm).round().clamp(0, model.headPixels);
  int get feedPixels => (lengthMm * model.pixelsPerMm).round();
  int get printableHeight => model.rotateForFeed ? crossFeedPixels : feedPixels;
  int get printableWidth => model.rotateForFeed ? feedPixels : crossFeedPixels;
  int get displayWidthMm => model.rotateForFeed ? lengthMm : widthMm;
  int get displayHeightMm => model.rotateForFeed ? widthMm : lengthMm;
  String get label => '$widthMm × $lengthMm mm';

  @override
  bool operator ==(Object other) =>
      other is LabelPaper &&
      model == other.model &&
      widthMm == other.widthMm &&
      lengthMm == other.lengthMm;
  @override
  int get hashCode => Object.hash(model, widthMm, lengthMm);
}
