import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';

class LabelEditor extends StatefulWidget {
  const LabelEditor({
    super.key,
    required this.controller,
    required this.layout,
    required this.unknown,
    required this.upsideDown,
    required this.onChanged,
    required this.keyboardInset,
  });

  final TextEditingController controller;
  final LabelLayout layout;
  final Set<String> unknown;
  final bool upsideDown;
  final ValueChanged<String> onChanged;
  final double keyboardInset;

  @override
  State<LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<LabelEditor> {
  final focusNode = FocusNode();
  Size? windowSize;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_revealEditor);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSize = MediaQuery.sizeOf(context);
    if (nextSize != windowSize) {
      windowSize = nextSize;
      _revealEditor();
    }
  }

  @override
  void didUpdateWidget(LabelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keyboardInset != oldWidget.keyboardInset) _revealEditor();
  }

  void _revealEditor() {
    if (!focusNode.hasFocus || widget.keyboardInset == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.hasFocus) return;
      final box = context.findRenderObject();
      final scrollable = Scrollable.maybeOf(context);
      // On very short screens, leave scrolling to the text field's caret.
      if (box is RenderBox &&
          box.hasSize &&
          scrollable != null &&
          box.size.height <= scrollable.position.viewportDimension) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final keyboardOpen = widget.keyboardInset > 0;
    final availableHeight =
        (MediaQuery.sizeOf(context).height -
                widget.keyboardInset -
                MediaQuery.paddingOf(context).vertical -
                kToolbarHeight)
            .clamp(0.0, double.infinity);
    final lineHeight = MediaQuery.textScalerOf(context)
        .scale(Theme.of(context).textTheme.bodyLarge!.fontSize!);
    final minLines = keyboardOpen
        ? (availableHeight * 0.3 / (lineHeight * 1.5)).floor().clamp(3, 6)
        : 6;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final width = wide
            ? (constraints.maxWidth - 24) / 2
            : constraints.maxWidth;
        return Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.labelPreview,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 420,
                        maxHeight: keyboardOpen ? availableHeight * 0.25 : 280,
                      ),
                      child: LabelPreview(
                        key: const ValueKey('label-preview'),
                        layout: widget.layout,
                        upsideDown: widget.upsideDown,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: wide ? 24 : 0, height: wide ? 0 : 12),
            SizedBox(
              width: width,
              child: TextField(
                key: const ValueKey('label-body'),
                controller: widget.controller,
                focusNode: focusNode,
                minLines: minLines,
                maxLines: keyboardOpen ? minLines : 12,
                maxLength: 8000,
                decoration: InputDecoration(
                  labelText: s.labelBody,
                  helperText: s.labelBodyHint,
                  helperMaxLines: 3,
                  errorText: widget.unknown.isEmpty
                      ? null
                      : s.shareTemplateUnknown(widget.unknown.join(', ')),
                  errorMaxLines: 3,
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        );
      },
    );
  }
}
