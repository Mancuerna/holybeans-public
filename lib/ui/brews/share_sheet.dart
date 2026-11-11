import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/share_clipboard.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:holybeans/ui/brews/share_brew_charts.dart';
import 'package:holybeans/ui/brews/share_sheet_controls.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';
import 'package:holybeans/ui/core/journal_share_card.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/share_image.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';
import 'package:holybeans/ui/core/share_photo_card.dart';
import 'package:holybeans/ui/core/share_photo_overlay.dart';

/// What the share sheet returns: the chosen fields and, in image mode, the
/// rendered PNG.
class ShareBrewResult {
  const ShareBrewResult({
    required this.fields,
    this.image,
    this.text,
    this.rememberFields = true,
  });

  final Set<BrewParameter> fields;
  final Uint8List? image;
  final String? text;
  final bool rememberFields;
}

class ShareBrewSheet extends StatefulWidget {
  const ShareBrewSheet({
    super.key,
    required this.coffee,
    required this.brew,
    required this.components,
    required this.initialFields,
    this.initialPhoto,
    this.cost,
    this.lot,
    this.method,
    this.recording,
    this.templateSettings,
    this.configuration,
    this.imageRenderer,
    this.toolNames = const [],
    this.clipboard = const ShareClipboard(),
  });

  final Uint8List? initialPhoto;
  final double? cost;
  final CoffeeLot? lot;
  final Coffee coffee;
  final Brew brew;
  final List<CoffeeComponent> components;
  final Set<BrewParameter> initialFields;
  final BrewMethod? method;
  final ({ShotCurve curve, String source})? recording;
  final List<String> toolNames;
  final ShareClipboard clipboard;
  final ShareTemplateSettings? templateSettings;
  final ShareConfiguration? configuration;
  final Future<Uint8List?> Function(
    BuildContext context,
    GlobalKey key, {
    Uint8List? photo,
  })?
  imageRenderer;

  @override
  State<ShareBrewSheet> createState() => _ShareBrewSheetState();
}

class _ShareBrewSheetState extends State<ShareBrewSheet> {
  late final selected = {...widget.initialFields};
  final cardKey = GlobalKey();
  bool asImage = false;
  bool transparent = false;
  bool lightText = true;
  bool photoCaption = false;
  bool photoOverlay = false;
  bool chartsOnPhoto = false;
  bool get overlayingCharts => photoCaption && chartsOnPhoto;
  bool get hasPhotoOverlay => photoOverlay || overlayingCharts;
  Alignment overlayAlignment = Alignment.bottomLeft;
  double overlayWidth = 0.65;
  late double overlayBackgroundOpacity =
      widget.configuration?.overlayBackgroundOpacity ??
      ShareConfiguration.defaultOverlayBackgroundOpacity;

  Future<void> _saveOverlayBackgroundOpacity(double value) async {
    try {
      await widget.templateSettings?.saveOverlayBackgroundOpacity(value);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).saveFailed)),
        );
      }
    }
  }

  bool get needsPhoto => asImage && hasPhotoOverlay && photo == null;
  late Uint8List? photo = widget.initialPhoto;
  bool pickingPhoto = false;
  bool copying = false;
  String? copyMessage;

  Future<void> _pickPhoto() async {
    if (busy) return;
    setState(() => pickingPhoto = true);
    try {
      final bytes = await pickSharePhoto(context);
      if (bytes == null) return;
      if (mounted) setState(() => photo = bytes);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).photoFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  bool includeCurve = false;
  bool includeMap = false;
  late final chartData = brewShareChartData(
    widget.brew,
    widget.method,
    widget.recording,
  );
  bool rendering = false;
  bool get busy => rendering || pickingPhoto || copying;
  late ShareConfiguration? configuration = widget.configuration;
  late String? templateId = configuration?.selected(style)?.id;
  ShareTemplateStyle get style =>
      isEspressoMethod(
        category: widget.method?.category,
        methodName: widget.method?.name ?? widget.brew.methodName,
      )
      ? ShareTemplateStyle.espresso
      : ShareTemplateStyle.filter;
  ShareTemplate? get template => configuration?.templates
      .where((t) => t.id == templateId && t.style == style)
      .firstOrNull;

  Future<void> _manage(Map<String, String> values) async {
    final settings = widget.templateSettings;
    if (busy || settings == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShareTemplatesPage(
          settings: settings,
          style: style,
          values: values,
        ),
      ),
    );
    try {
      final next = await settings.load();
      if (mounted) {
        setState(() {
          configuration = next;
          templateId = next.selected(style)?.id;
        });
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).shareTemplateLoadFailed),
          ),
        );
      }
    }
  }

  Future<void> _share(String source) async {
    if (busy) return;
    setState(() => rendering = true);
    if (!asImage) {
      Navigator.pop(
        context,
        ShareBrewResult(
          fields: selected,
          text: source,
          rememberFields: template == null,
        ),
      );
      return;
    }
    try {
      final bytes = await (widget.imageRenderer ?? renderShareImage)(
        context,
        cardKey,
        photo: photoCaption || photoOverlay ? photo : null,
      );
      if (!mounted) return;
      if (bytes == null) throw StateError('Image capture failed');
      Navigator.pop(
        context,
        ShareBrewResult(
          fields: selected,
          image: bytes,
          text: photoCaption ? source : null,
          rememberFields: template == null,
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => rendering = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
        );
      }
    }
  }

  Future<void> _copy(String source) async {
    if (busy || source.isEmpty) return;
    final s = AppLocalizations.of(context);
    setState(() {
      copying = true;
      copyMessage = null;
    });
    try {
      if (asImage) {
        final bytes = await (widget.imageRenderer ?? renderShareImage)(
          context,
          cardKey,
          photo: photoCaption || photoOverlay ? photo : null,
        );
        if (!mounted) return;
        if (bytes == null) throw StateError('Image capture failed');
        await widget.clipboard.copyImage(bytes);
      } else {
        await widget.clipboard.copyText(source);
      }
      if (mounted) {
        setState(
          () => copyMessage = asImage ? s.shareImageCopied : s.shareTextCopied,
        );
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => copyMessage = s.shareCopyFailed);
    } finally {
      if (mounted) setState(() => copying = false);
    }
  }

  /// What will be shared: the picture, the text, or why there is nothing.
  Widget _preview(
    AppLocalizations s,
    List<List<(String, String)>> sections,
    String source,
    String? markdown,
  ) {
    if (source.isEmpty) return Text(s.noShareFields);
    if (!asImage) return SelectableText(source);
    if (photoCaption) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: overlayingCharts && photo == null
                ? Text(s.shareChartsOverlayHint)
                : ShareImagePreview(
                    captureKey: cardKey,
                    transparent: transparent || overlayingCharts,
                    lightText: lightText,
                    child: overlayingCharts
                        ? SharePhotoOverlay(
                            photo: photo!,
                            alignment: overlayAlignment,
                            widthFraction: overlayWidth,
                            backgroundOpacity: 0,
                            child: BrewShareCharts(
                              data: chartData,
                              includeCurve: includeCurve,
                              includeMap: includeMap,
                              panelBackgroundOpacity: overlayBackgroundOpacity,
                            ),
                          )
                        : SharePhotoCard(
                            photo: photo,
                            title: widget.coffee.name,
                            charts: BrewShareCharts(
                              data: chartData,
                              includeCurve: includeCurve,
                              includeMap: includeMap,
                            ),
                          ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(s.sharePhotoCaptionHint),
          const SizedBox(height: 8),
          SelectableText(source),
        ],
      );
    }
    final card = BrewShareCard(
      title: widget.coffee.name,
      sections: sections,
      customText: markdown,
      charts: BrewShareCharts(
        data: chartData,
        includeCurve: includeCurve,
        includeMap: includeMap,
      ),
    );
    if (photoOverlay && photo == null) return Text(s.sharePhotoOverlayHint);
    return Center(
      child: ShareImagePreview(
        captureKey: cardKey,
        transparent: transparent || photoOverlay,
        lightText: lightText,
        child: photoOverlay
            ? SharePhotoOverlay(
                photo: photo!,
                alignment: overlayAlignment,
                widthFraction: overlayWidth,
                backgroundOpacity: overlayBackgroundOpacity,
                child: card,
              )
            : card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = math.min(
      screenHeight * 0.88,
      screenHeight - MediaQuery.paddingOf(context).top - 20,
    );
    final sections = BrewShareText.buildSections(
      strings: s,
      cost: widget.cost,
      coffee: widget.coffee,
      brew: widget.brew,
      components: widget.components,
      method: widget.method,
      toolNames: widget.toolNames,
      fields: selected,
      dateLocaleName: regionalLocale.toString(),
    );
    final values = shareTemplateValues(
      lot: widget.lot,
      strings: s,
      cost: widget.cost,
      coffee: widget.coffee,
      brew: widget.brew,
      components: widget.components,
      method: widget.method,
      toolNames: widget.toolNames,
      dateLocaleName: regionalLocale.toString(),
    );
    final template = this.template;
    final source = template == null
        ? BrewShareText.formatSections(sections)
        : TemplateEngine.render(template.body, values);
    final missing = template == null
        ? <String>{}
        : TemplateEngine.missingTags(template.body, values);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            ShareSheetHeader(
              asImage: asImage,
              onChanged: busy
                  ? null
                  : (value) => setState(() => asImage = value),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (configuration?.templates.any((t) => t.style == style) ??
                        false)
                      _ShareTemplateChoice(
                        templates: configuration!.templates
                            .where((t) => t.style == style)
                            .toList(),
                        selected: template?.id,
                        onChanged: busy
                            ? null
                            : (id) => setState(() => templateId = id),
                      ),
                    if (widget.templateSettings != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('share-manage-templates'),
                          onPressed: busy ? null : () => _manage(values),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: Text(s.shareTemplateManage),
                        ),
                      ),
                    if (missing.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          s.shareTemplateMissing(
                            missing.map((t) => '<$t>').join(', '),
                          ),
                        ),
                      ),
                    if (asImage) ...[
                      if (!hasPhotoOverlay)
                        ShareImageOptions(
                          transparent: transparent,
                          lightText: lightText,
                          enabled: !busy,
                          onTransparentChanged: (value) =>
                              setState(() => transparent = value),
                          onLightTextChanged: (value) =>
                              setState(() => lightText = value),
                        ),
                      SwitchListTile(
                        key: const ValueKey('share-photo-overlay'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.sharePhotoOverlay),
                        value: photoOverlay,
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                photoOverlay = value;
                                if (value) photoCaption = false;
                              }),
                      ),
                      SwitchListTile(
                        key: const ValueKey('share-photo-caption'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.sharePhotoCaption),
                        value: photoCaption,
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                photoCaption = value;
                                if (value) photoOverlay = false;
                              }),
                      ),
                      if (photoCaption)
                        SwitchListTile(
                          key: const ValueKey('share-charts-overlay'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.shareChartsOverlay),
                          subtitle: Text(s.shareChartsOverlayHint),
                          value: chartsOnPhoto,
                          onChanged: busy
                              ? null
                              : (value) =>
                                    setState(() => chartsOnPhoto = value),
                        ),
                      if (hasPhotoOverlay)
                        SharePhotoOverlayOptions(
                          positionLabel: overlayingCharts
                              ? s.shareChartOverlayPosition
                              : null,
                          sizeLabel: overlayingCharts
                              ? s.shareChartOverlaySize
                              : null,
                          alignment: overlayAlignment,
                          widthFraction: overlayWidth,
                          backgroundOpacity: overlayBackgroundOpacity,
                          onBackgroundOpacityChanged: (value) =>
                              setState(() => overlayBackgroundOpacity = value),
                          onBackgroundOpacityChangeEnd:
                              _saveOverlayBackgroundOpacity,
                          lightText: lightText,
                          enabled: !busy,
                          onAlignmentChanged: (value) =>
                              setState(() => overlayAlignment = value),
                          onWidthChanged: (value) =>
                              setState(() => overlayWidth = value),
                          onLightTextChanged: (value) =>
                              setState(() => lightText = value),
                        ),
                      if (photoCaption || photoOverlay)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              key: const ValueKey('share-choose-photo'),
                              onPressed: busy ? null : _pickPhoto,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                photo == null ? s.addPhoto : s.changePhoto,
                              ),
                            ),
                            if (photo != null)
                              TextButton(
                                key: const ValueKey('share-remove-photo'),
                                onPressed: busy
                                    ? null
                                    : () => setState(() => photo = null),
                                child: Text(s.removePhoto),
                              ),
                          ],
                        ),
                    ],
                    if (asImage)
                      ShareChartOptions(
                        data: chartData,
                        curveSelected: includeCurve,
                        mapSelected: includeMap,
                        enabled: !busy,
                        onCurveChanged: (on) =>
                            setState(() => includeCurve = on),
                        onMapChanged: (on) => setState(() => includeMap = on),
                      ),
                    _preview(
                      s,
                      sections,
                      source,
                      template == null
                          ? null
                          : TemplateEngine.renderMarkdown(
                              template.body,
                              values,
                            ),
                    ),
                    const SizedBox(height: 18),
                    if (template == null)
                      _ShareFields(
                        selected: selected,
                        enabled: !busy,
                        onChanged: (field, on) => setState(() {
                          if (on) {
                            selected.add(field);
                          } else {
                            selected.remove(field);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            ShareSheetActions(
              busy: busy,
              onShare: source.isEmpty || busy || needsPhoto
                  ? null
                  : () => _share(source),
              onCopy:
                  source.isEmpty ||
                      needsPhoto ||
                      busy ||
                      (asImage && !widget.clipboard.supportsImages)
                  ? null
                  : () => _copy(source),
              copyLabel: asImage && !widget.clipboard.supportsImages
                  ? s.shareImageCopyUnavailable
                  : asImage
                  ? s.shareCopyImage
                  : s.shareCopyText,
              message: copyMessage,
            ),
          ],
        ),
      ),
    );
  }
}

/// A shareable picture built from the same complete fields as the text share.
class BrewShareCard extends StatelessWidget {
  const BrewShareCard({
    super.key,
    required this.title,
    required this.sections,
    this.customText,
    this.charts,
  });
  final String title;
  final List<List<(String, String)>> sections;
  final String? customText;
  final Widget? charts;

  @override
  Widget build(BuildContext context) {
    final coffeeLabel = BrewParameter.coffee.label(
      AppLocalizations.of(context),
    );
    return JournalShareCard(
      key: const ValueKey('brew-share-card'),
      title: title,
      sections: [
        for (final section in sections)
          [
            for (final row in section)
              if (!(row.$1 == coffeeLabel && row.$2 == title)) row,
          ],
      ],
      customText: customText,
      charts: charts,
    );
  }
}

class _ShareFields extends StatelessWidget {
  const _ShareFields({
    required this.selected,
    required this.onChanged,
    required this.enabled,
  });
  final Set<BrewParameter> selected;
  final void Function(BrewParameter, bool) onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(s.shareFields),
      subtitle: Text(s.shareFieldsSettingsHint),
      tilePadding: EdgeInsets.zero,
      children: [
        for (final group in BrewParameterGroup.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                group.label(s),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
          for (final field in BrewParameter.values)
            if (field.group == group && field.canShare)
              CheckboxListTile(
                key: ValueKey('share-field-${field.name}'),
                title: Text(field.label(s)),
                dense: true,
                value: selected.contains(field),
                onChanged: enabled
                    ? (value) => onChanged(field, value == true)
                    : null,
              ),
        ],
      ],
    );
  }
}

class _ShareTemplateChoice extends StatelessWidget {
  const _ShareTemplateChoice({
    required this.templates,
    required this.selected,
    required this.onChanged,
  });

  final List<ShareTemplate> templates;
  final String? selected;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      key: ValueKey('share-template-$selected'),
      initialValue: selected ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: s.shareTemplateChoice),
      items: [
        DropdownMenuItem(value: '', child: Text(s.shareTemplateFields)),
        for (final template in templates)
          DropdownMenuItem(
            value: template.id,
            child: Text(template.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (id) => onChanged!(id == '' ? null : id),
    );
  }
}
