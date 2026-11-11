import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';

class SharePhotoOverlay extends StatelessWidget {
  const SharePhotoOverlay({
    super.key,
    required this.photo,
    required this.alignment,
    required this.widthFraction,
    required this.backgroundOpacity,
    required this.child,
  });

  final Uint8List photo;
  final Alignment alignment;
  final double widthFraction;
  final double backgroundOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('share-photo-overlay-card'),
      width: 340,
      child: Stack(
        children: [
          // The photo determines the canvas ratio, without cropping it.
          Image.memory(
            photo,
            width: 340,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => SizedBox(
              height: 255,
              child: Center(
                child: Text(AppLocalizations.of(context).photoFailed),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: alignment,
                child: FractionallySizedBox(
                  widthFactor: widthFraction,
                  child: FittedBox(
                    // Long templates and charts must also fit inside the photo.
                    fit: BoxFit.scaleDown,
                    alignment: alignment,
                    child: ShareOverlayPanel(
                      backgroundOpacity: backgroundOpacity,
                      child: SizedBox(width: 340, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShareOverlayPanel extends StatelessWidget {
  const ShareOverlayPanel({
    super.key,
    required this.backgroundOpacity,
    required this.child,
  });

  final double backgroundOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color:
          (Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white)
              .withValues(alpha: backgroundOpacity),
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}

class SharePhotoOverlayOptions extends StatelessWidget {
  const SharePhotoOverlayOptions({
    super.key,
    required this.alignment,
    required this.widthFraction,
    required this.backgroundOpacity,
    required this.lightText,
    required this.enabled,
    required this.onAlignmentChanged,
    required this.onWidthChanged,
    required this.onLightTextChanged,
    required this.onBackgroundOpacityChanged,
    required this.onBackgroundOpacityChangeEnd,
    this.positionLabel,
    this.sizeLabel,
  });

  final Alignment alignment;
  final double widthFraction;
  final double backgroundOpacity;
  final bool lightText;
  final bool enabled;
  final ValueChanged<Alignment> onAlignmentChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<bool> onLightTextChanged;
  final ValueChanged<double> onBackgroundOpacityChanged;
  final ValueChanged<double> onBackgroundOpacityChangeEnd;
  final String? positionLabel;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final positions = {
      Alignment.topLeft: s.shareOverlayTopLeft,
      Alignment.topRight: s.shareOverlayTopRight,
      Alignment.centerLeft: s.shareOverlayCenterLeft,
      Alignment.centerRight: s.shareOverlayCenterRight,
      Alignment.bottomLeft: s.shareOverlayBottomLeft,
      Alignment.bottomRight: s.shareOverlayBottomRight,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShareTextColorOptions(
          lightText: lightText,
          onChanged: enabled ? onLightTextChanged : null,
        ),
        const SizedBox(height: 12),
        Text(
          '${s.shareOverlayBackgroundOpacity}: '
          '${(backgroundOpacity * 100).round()}%',
        ),
        Slider(
          key: const ValueKey('share-overlay-background-opacity'),
          value: backgroundOpacity,
          divisions: 20,
          label: '${(backgroundOpacity * 100).round()}%',
          semanticFormatterCallback: (value) =>
              '${s.shareOverlayBackgroundOpacity}: ${(value * 100).round()}%',
          onChanged: enabled ? onBackgroundOpacityChanged : null,
          onChangeEnd: enabled ? onBackgroundOpacityChangeEnd : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Alignment>(
          key: const ValueKey('share-overlay-position'),
          initialValue: alignment,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: positionLabel ?? s.shareOverlayPosition,
          ),
          items: [
            for (final position in positions.entries)
              DropdownMenuItem(
                value: position.key,
                child: Text(position.value),
              ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onAlignmentChanged(value);
                }
              : null,
        ),
        const SizedBox(height: 12),
        Text(sizeLabel ?? s.shareOverlaySize),
        Slider(
          key: const ValueKey('share-overlay-size'),
          value: widthFraction,
          min: 0.4,
          divisions: 12,
          label: '${(widthFraction * 100).round()}%',
          semanticFormatterCallback: (value) =>
              '${sizeLabel ?? s.shareOverlaySize}: ${(value * 100).round()}%',
          onChanged: enabled ? onWidthChanged : null,
        ),
      ],
    );
  }
}
