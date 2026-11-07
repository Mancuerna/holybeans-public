import 'package:flutter/material.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_graphic_controller.dart';

class LabelOutputSettings extends StatelessWidget {
  const LabelOutputSettings({
    super.key,
    required this.printers,
    required this.printer,
    required this.paper,
    required this.onPrinter,
    required this.onPaper,
  });
  final List<LabelPrinter> printers;
  final LabelPrinter printer;
  final LabelPaper paper;
  final ValueChanged<LabelPrinter> onPrinter;
  final ValueChanged<LabelPaper> onPaper;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<LabelPrinter>(
          key: ValueKey(printer.model),
          initialValue: printer,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.labelPrinterModel),
          items: [
            for (final item in printers)
              DropdownMenuItem(
                value: item,
                child: Text(
                  'Niimbot ${item.model.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onPrinter(value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<LabelPaper>(
          key: ValueKey('label-paper-${printer.model.name}'),
          initialValue: paper,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.labelPaper),
          items: [
            for (final value in printer.model.papers)
              DropdownMenuItem(
                value: value,
                child: Text(
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onPaper(value);
          },
        ),
        const SizedBox(height: 8),
        Text(s.labelPaperHint),
        if (printer.model != LabelPrinterModel.d110)
          Text(s.labelModelTrial(printer.model.label)),
        if (printer.model == LabelPrinterModel.b21) Text(s.labelB21Variants),
        if (printer.model == LabelPrinterModel.b2) Text(s.labelB2Protocol),
      ],
    );
  }
}

class LabelGraphicControls extends StatelessWidget {
  const LabelGraphicControls({
    super.key,
    required this.graphic,
    required this.options,
    required this.onOptions,
  });
  final LabelGraphicController graphic;
  final LabelImageOptions options;
  final ValueChanged<LabelImageOptions> onOptions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('label-image-pick'),
              onPressed: graphic.loading ? null : graphic.pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(s.labelImageChoose),
            ),
            if (graphic.data != null || graphic.failed)
              TextButton.icon(
                key: const ValueKey('label-image-remove'),
                onPressed: graphic.loading ? null : () => graphic.load(null),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.labelImageRemove),
              ),
          ],
        ),
        Text(s.labelImageHint),
        if (graphic.data != null && !graphic.failed) ...[
          const SizedBox(height: 12),
          _choice<LabelImagePosition>(
            'label-image-position',
            s.labelImagePosition,
            options.position,
            {
              LabelImagePosition.top: s.labelImageAbove,
              LabelImagePosition.left: s.labelImageLeft,
              LabelImagePosition.right: s.labelImageRight,
            },
            (value) => onOptions(options.copyWith(position: value)),
          ),
          const SizedBox(height: 12),
          _choice<LabelImageAlignment>(
            'label-image-alignment',
            s.labelImageAlignment,
            options.alignment,
            {
              LabelImageAlignment.start:
                  options.position == LabelImagePosition.top
                  ? s.labelImageLeft
                  : s.labelImageAbove,
              LabelImageAlignment.center: s.labelImageCenter,
              LabelImageAlignment.end:
                  options.position == LabelImagePosition.top
                  ? s.labelImageRight
                  : s.labelImageBelow,
            },
            (value) => onOptions(options.copyWith(alignment: value)),
          ),
          const SizedBox(height: 12),
          _offsetSlider(
            'label-image-offset-x',
            s.labelImageOffsetX,
            options.offsetX,
            (value) => onOptions(options.copyWith(offsetX: value)),
          ),
          _offsetSlider(
            'label-image-offset-y',
            s.labelImageOffsetY,
            options.offsetY,
            (value) => onOptions(options.copyWith(offsetY: value)),
          ),
          Text(s.labelImageOffsetHint),
          TextButton.icon(
            key: const ValueKey('label-image-offset-reset'),
            onPressed: options.offsetX == 0 && options.offsetY == 0
                ? null
                : () => onOptions(options.copyWith(offsetX: 0, offsetY: 0)),
            icon: const Icon(Icons.restart_alt),
            label: Text(s.labelImageOffsetReset),
          ),
          Text('${s.labelImageSize}: ${(options.size * 100).round()} %'),
          Slider(
            key: const ValueKey('label-image-size'),
            value: options.size,
            min: 0.1,
            divisions: 18,
            label: '${(options.size * 100).round()} %',
            semanticFormatterCallback: (value) =>
                '${s.labelImageSize}: ${(value * 100).round()} %',
            onChanged: (value) => onOptions(options.copyWith(size: value)),
          ),
          _choice<LabelImageMode>(
            'label-image-mode',
            s.labelImageTreatment,
            options.mode,
            {
              LabelImageMode.logo: s.labelImageLogo,
              LabelImageMode.photo: s.labelImagePhoto,
            },
            (value) => onOptions(options.copyWith(mode: value)),
          ),
          const SizedBox(height: 8),
          Text(
            options.mode == LabelImageMode.logo
                ? s.labelImageLogoHint
                : s.labelImagePhotoHint,
          ),
          const SizedBox(height: 12),
          Text(
            '${s.labelImageContrast}: ${(options.contrast * 100).round()} %',
          ),
          Slider(
            key: const ValueKey('label-image-contrast'),
            value: options.contrast,
            min: 0.5,
            max: 2,
            divisions: 30,
            label: '${(options.contrast * 100).round()} %',
            semanticFormatterCallback: (value) =>
                '${s.labelImageContrast}: ${(value * 100).round()} %',
            onChanged: (value) => onOptions(options.copyWith(contrast: value)),
          ),
        ],
        if (graphic.loading) const LinearProgressIndicator(),
        if (graphic.failed)
          Text(
            s.labelImageFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _offsetSlider(
    String key,
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${(value * 100).round()} %'),
      Slider(
        key: ValueKey(key),
        value: value,
        min: -1,
        divisions: 200,
        label: '${(value * 100).round()} %',
        semanticFormatterCallback: (value) =>
            '$label: ${(value * 100).round()} %',
        onChanged: onChanged,
      ),
    ],
  );

  Widget _choice<T>(
    String key,
    String label,
    T value,
    Map<T, String> choices,
    ValueChanged<T> onChanged,
  ) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        key: ValueKey(key),
        value: value,
        isExpanded: true,
        isDense: true,
        items: [
          for (final entry in choices.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ),
  );
}
