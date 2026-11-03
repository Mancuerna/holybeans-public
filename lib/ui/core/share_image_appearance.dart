import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class ShareImageOptions extends StatelessWidget {
  const ShareImageOptions({
    super.key,
    required this.transparent,
    required this.lightText,
    required this.enabled,
    required this.onTransparentChanged,
    required this.onLightTextChanged,
  });

  final bool transparent;
  final bool lightText;
  final bool enabled;
  final ValueChanged<bool> onTransparentChanged;
  final ValueChanged<bool> onLightTextChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('share-transparent-background'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.shareTransparentBackground),
          value: transparent,
          onChanged: enabled ? onTransparentChanged : null,
        ),
        if (transparent) ...[
          Text(s.shareTransparentHint),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final light in [true, false])
                ChoiceChip(
                  key: ValueKey(light ? 'share-light-text' : 'share-dark-text'),
                  label: Text(light ? s.shareLightText : s.shareDarkText),
                  selected: lightText == light,
                  onSelected: enabled ? (_) => onLightTextChanged(light) : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class ShareImagePreview extends StatelessWidget {
  const ShareImagePreview({
    super.key,
    required this.captureKey,
    required this.transparent,
    required this.lightText,
    required this.child,
  });

  final GlobalKey captureKey;
  final bool transparent;
  final bool lightText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = lightText ? Colors.white : Colors.black;
    final scheme = ColorScheme.fromSeed(
      seedColor: theme.colorScheme.primary,
      brightness: lightText ? Brightness.dark : Brightness.light,
    );
    return CustomPaint(
      // Keep the checkerboard outside the boundary used to export the PNG.
      painter: transparent ? const _TransparencyPainter() : null,
      child: RepaintBoundary(
        key: captureKey,
        child: ShareImageAppearance(
          transparent: transparent,
          child: Theme(
            data: transparent
                ? theme.copyWith(
                    colorScheme: scheme.copyWith(
                      primary: foreground,
                      onSurface: foreground,
                      onSurfaceVariant: foreground,
                      outlineVariant: foreground.withValues(alpha: 0.4),
                    ),
                    textTheme: theme.textTheme.apply(
                      bodyColor: foreground,
                      displayColor: foreground,
                    ),
                  )
                : theme,
            child: child,
          ),
        ),
      ),
    );
  }
}

class ShareImageAppearance extends InheritedWidget {
  const ShareImageAppearance({
    super.key,
    required this.transparent,
    required super.child,
  });

  final bool transparent;

  static bool isTransparent(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ShareImageAppearance>()
          ?.transparent ??
      false;

  @override
  bool updateShouldNotify(ShareImageAppearance oldWidget) =>
      transparent != oldWidget.transparent;
}

class _TransparencyPainter extends CustomPainter {
  const _TransparencyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 12.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint();
    for (var row = 0; row * tile < size.height; row++) {
      for (var column = 0; column * tile < size.width; column++) {
        paint.color = (row + column).isEven
            ? const Color(0xff8a8a8a)
            : const Color(0xffa3a3a3);
        canvas.drawRect(
          Rect.fromLTWH(column * tile, row * tile, tile, tile),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TransparencyPainter oldDelegate) => false;
}
