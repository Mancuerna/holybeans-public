import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/domain/label_raster.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_text.dart';
import 'package:holybeans/ui/labels/label_text_flow.dart';

class LabelBitmap {
  const LabelBitmap(this.width, this.pixels, this.png);
  final int width;
  final Uint8List pixels;
  final Uint8List png;
}

class LabelLayout {
  LabelLayout(
    this.markdown,
    this.paper, {
    this.graphic,
    LabelImageOptions? imageOptions,
  }) : imageOptions =
           imageOptions ??
           LabelImageOptions(size: markdown.trim().isEmpty ? 1 : 0.4) {
    this.imageOptions.validate();
    if (markdown.trim().isEmpty) {
      fitsPaper = graphic != null;
      return;
    }
    for (var size = 22.0; size >= 14; size -= 1) {
      if (_flowsAroundImage) {
        final flow = LabelTextFlow(
          _span(size),
          contentBounds,
          graphicBounds.inflate(4),
          left: this.imageOptions.position == LabelImagePosition.left,
        );
        _flow = flow;
        if (flow.fits) {
          fontSize = size;
          fitsPaper = true;
          break;
        }
        continue;
      }
      final text = _text(size);
      final fits = textBounds.width > 0 && text.height <= textHeight;
      text.dispose();
      if (fits) {
        fontSize = size;
        fitsPaper = true;
        break;
      }
    }
  }

  final String markdown;
  final LabelPaper paper;
  double get scale => paper.model.pixelsPerMm / 8;
  double get width => paper.printableWidth / scale;
  double get height => paper.printableHeight / scale;
  final ui.Image? graphic;
  final LabelImageOptions imageOptions;
  Rect get contentBounds => Rect.fromLTWH(4, 4, width - 8, height - 8);
  Rect get graphicSlot {
    final area = contentBounds;
    if (markdown.trim().isEmpty) {
      return area;
    }
    return switch (imageOptions.position) {
      LabelImagePosition.top => Rect.fromLTWH(
        area.left,
        area.top,
        area.width,
        area.height * imageOptions.size,
      ),
      LabelImagePosition.left => Rect.fromLTWH(
        area.left,
        area.top,
        area.width * imageOptions.size,
        area.height,
      ),
      LabelImagePosition.right => Rect.fromLTWH(
        area.right - area.width * imageOptions.size,
        area.top,
        area.width * imageOptions.size,
        area.height,
      ),
    };
  }

  Rect get graphicBounds {
    final graphic = this.graphic;
    if (graphic == null) return Rect.zero;
    final source = Size(graphic.width.toDouble(), graphic.height.toDouble());
    final targetSize = markdown.trim().isEmpty
        ? graphicSlot.size * imageOptions.size
        : graphicSlot.size;
    final fitted = applyBoxFit(BoxFit.contain, source, targetSize);
    final offset = switch (imageOptions.alignment) {
      LabelImageAlignment.start => -1.0,
      LabelImageAlignment.center => 0.0,
      LabelImageAlignment.end => 1.0,
    };
    final alignment = imageOptions.position == LabelImagePosition.top
        ? Alignment(offset, 0)
        : Alignment(0, offset);
    final base = alignment.inscribe(fitted.destination, graphicSlot);
    final area = contentBounds;
    // Move from the preset toward each printable edge without cropping.
    double shifted(double start, double min, double max, double offset) =>
        start + (offset < 0 ? start - min : max - start) * offset;
    final rect = Rect.fromLTWH(
      shifted(
        base.left,
        area.left,
        area.right - base.width,
        imageOptions.offsetX,
      ),
      shifted(
        base.top,
        area.top,
        area.bottom - base.height,
        imageOptions.offsetY,
      ),
      base.width,
      base.height,
    );
    // Snap the image to printer dots, including on 300 dpi models.
    return Rect.fromLTRB(
      (rect.left * scale).round() / scale,
      (rect.top * scale).round() / scale,
      (rect.right * scale).round() / scale,
      (rect.bottom * scale).round() / scale,
    );
  }

  Rect get textBounds {
    final area = contentBounds;
    if (graphic == null || markdown.trim().isEmpty) return area;
    final bottom = graphicBounds.bottom > graphicSlot.bottom
        ? graphicBounds.bottom
        : graphicSlot.bottom;
    return switch (imageOptions.position) {
      LabelImagePosition.top => Rect.fromLTWH(
        area.left,
        bottom + 4,
        area.width,
        (area.bottom - bottom - 4).clamp(0, area.height),
      ),
      LabelImagePosition.left || LabelImagePosition.right => area,
    };
  }

  double get textTop => textBounds.top;
  double get textHeight => textBounds.height;
  bool get _flowsAroundImage =>
      graphic != null && imageOptions.position != LabelImagePosition.top;
  LabelTextFlow? _flow;
  List<LabelFlowLine> get textLines => List.unmodifiable(_flow?.lines ?? []);
  Future<LabelBitmap>? _preview;
  Future<LabelBitmap> get previewBitmap => _preview ??= _rasterize();
  double fontSize = 14;
  bool fitsPaper = false;

  TextSpan _span(double size) => TextSpan(
    style: TextStyle(
      color: Colors.black,
      fontFamily: 'Plex',
      fontFamilyFallback: const ['NotoEmoji'],
      fontSize: size,
      height: 1.1,
    ),
    children: [labelMarkdownSpan(markdown)],
  );

  TextPainter _text(double size) =>
      TextPainter(text: _span(size), textDirection: TextDirection.ltr)
        ..layout(maxWidth: textBounds.width);

  void paint(Canvas canvas) {
    canvas.save();
    canvas.scale(scale);
    final bounds = Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRect(bounds);
    final graphic = this.graphic;
    if (graphic != null) {
      final source = Size(graphic.width.toDouble(), graphic.height.toDouble());

      canvas.drawImageRect(
        graphic,
        Offset.zero & source,
        graphicBounds,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    if (markdown.trim().isNotEmpty) {
      if (_flow case final flow?) {
        canvas.save();
        canvas.clipRect(contentBounds);
        flow.paint(canvas);
        canvas.restore();
      } else {
        final text = _text(fontSize);
        canvas.save();
        canvas.clipRect(textBounds);
        text.paint(
          canvas,
          Offset(
            textBounds.left,
            fitsPaper ? textTop + (textHeight - text.height) / 2 : textTop,
          ),
        );
        text.dispose();
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  Future<LabelBitmap> rasterize({bool upsideDown = false}) async {
    if (!fitsPaper) throw StateError('Label content does not fit');
    return upsideDown ? _rasterize(upsideDown: true) : previewBitmap;
  }

  Future<LabelBitmap> _rasterize({bool upsideDown = false}) async {
    final graphicRect = graphic == null ? null : graphicBounds;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas);
    final picture = recorder.endRecording();
    final width = paper.printableWidth;
    final height = paper.printableHeight;
    final image = await picture.toImage(width, height);
    picture.dispose();
    final rgba = (await image.toByteData())!;
    image.dispose();
    final (:pixels, rgba: monochrome) = await compute(prepareLabelRaster, (
      rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: width,
      options: imageOptions,
      graphic: graphicRect == null
          ? null
          : (
              left: (graphicRect.left * scale).round(),
              top: (graphicRect.top * scale).round(),
              right: (graphicRect.right * scale).round(),
              bottom: (graphicRect.bottom * scale).round(),
            ),
      upsideDown: upsideDown,
    ), debugLabel: 'label-raster');
    final buffer = await ui.ImmutableBuffer.fromUint8List(monochrome);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png = (await frame.image.toByteData(format: ui.ImageByteFormat.png))!;
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return LabelBitmap(width, pixels, png.buffer.asUint8List());
  }
}

class LabelPreview extends StatefulWidget {
  const LabelPreview({
    super.key,
    required this.layout,
    this.upsideDown = false,
  });
  final LabelLayout layout;
  final bool upsideDown;

  @override
  State<LabelPreview> createState() => _LabelPreviewState();
}

class _LabelPreviewState extends State<LabelPreview> {
  late Future<LabelBitmap> _preview;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _preview = widget.layout.previewBitmap;
  }

  @override
  void didUpdateWidget(LabelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.layout, widget.layout)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      setState(() {
        _preview = widget.layout.previewBitmap;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    return Semantics(
      image: true,
      child: ColoredBox(
        color: Colors.white,
        child: AspectRatio(
          aspectRatio:
              layout.paper.displayWidthMm / layout.paper.displayHeightMm,
          child: Center(
            child: FractionallySizedBox(
              heightFactor:
                  (layout.paper.printableHeight /
                          (layout.paper.displayHeightMm *
                              layout.paper.model.pixelsPerMm))
                      .clamp(0.0, 1.0),
              widthFactor:
                  (layout.paper.printableWidth /
                          (layout.paper.displayWidthMm *
                              layout.paper.model.pixelsPerMm))
                      .clamp(0.0, 1.0),
              child: RotatedBox(
                quarterTurns: widget.upsideDown ? 2 : 0,
                child: FutureBuilder<LabelBitmap>(
                  future: _preview,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          AppLocalizations.of(context).labelExportFailed,
                        ),
                      );
                    }
                    final bitmap = snapshot.data;
                    if (bitmap == null) return const SizedBox.expand();
                    return Image.memory(
                      bitmap.png,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
