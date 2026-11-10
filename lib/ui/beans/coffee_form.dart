import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_resizer.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';
import 'package:holybeans/domain/web_link.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/coffee_form_model.dart';
import 'package:holybeans/ui/beans/coffee_origin_card.dart';
import 'package:holybeans/ui/beans/coffee_origin_draft.dart';
import 'package:holybeans/ui/beans/freezer_widgets.dart';
import 'package:holybeans/ui/core/flavor_notes_field.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/form_validation.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/suggested_text_field.dart';

class CoffeeForm extends StatefulWidget {
  const CoffeeForm({
    super.key,
    required this.repository,
    this.existing,
    this.components = const [],
    this.lots = const [],
    this.photos,
    this.savedPhotos = const [],
    this.card,
    this.initialNotes,
    this.roastLevelHint,
    this.importPhoto,
  });

  final JournalRepository repository;
  final Coffee? existing;

  /// A coffee card someone shared, to fill a new coffee from.
  final SharedBean? card;
  final String? initialNotes;
  final String? roastLevelHint;
  final Future<Uint8List> Function()? importPhoto;
  final List<CoffeeComponent> components;
  final List<CoffeeLot> lots;

  /// Photo folder; the photo control is hidden without it.
  final PhotoStore? photos;

  /// Photo files of [existing], in order.
  final List<String> savedPhotos;

  @override
  State<CoffeeForm> createState() => _CoffeeFormState();
}

class _CoffeeFormState extends State<CoffeeForm> {
  final formKey = GlobalKey<FormState>();
  CoffeeSuggestions? suggestions;
  late final model = CoffeeFormModel(
    repository: widget.repository,
    existing: widget.existing,
    card: widget.card,
    initialNotes: widget.initialNotes,
    components: widget.components,
    lots: widget.lots,
    photoStore: widget.photos,
    savedPhotos: widget.savedPhotos,
  );
  bool importingPhoto = false;
  bool catalogPhotoAdded = false;

  Future<void> _importPhoto() async {
    final store = widget.photos;
    final load = widget.importPhoto;
    if (store == null || load == null || importingPhoto) return;
    setState(() => importingPhoto = true);
    try {
      final added = await model.photos.pick(() async {
        final bytes = await shrinkPhoto(await load());
        return store.add(bytes);
      });
      if (mounted && added) setState(() => catalogPhotoAdded = true);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.loffeePhotoFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => importingPhoto = false);
    }
  }

  void _photosChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    model.addListener(_photosChanged);
    _loadSuggestions();
    if (model.selectedRoastDate != null) {
      model.roastDate.text = formatRegionalDate(
        model.selectedRoastDate!,
        regionalLocale,
      );
    }
    model.initialGrams.addListener(_refreshPricePerKg);
    model.paidPrice.addListener(_refreshPricePerKg);
  }

  Future<void> _loadSuggestions() async {
    try {
      final loaded = await widget.repository.coffeeSuggestions();
      if (mounted) setState(() => suggestions = loaded);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.dataError,
        );
      }
    }
  }

  void _refreshPricePerKg() {
    if (mounted) setState(() {});
  }

  double? get _startingGrams {
    if (widget.existing == null) return parseNumber(model.initialGrams.text);
    if (widget.lots.isEmpty) return parseNumber(model.initialGrams.text);
    if (widget.lots.length == 1) return parseNumber(model.initialGrams.text);
    if (widget.lots.any((lot) => lot.initialGrams == null)) {
      return null;
    }
    return widget.lots.fold<double>(0, (sum, lot) => sum + lot.initialGrams!);
  }

  double? get _pricePerKg => pricePerKgFor(
    paidPriceCents: parsePriceCents(model.paidPrice.text),
    initialGrams: _startingGrams,
  );

  Future<void> chooseRoastDate() async {
    final deviceLocale = regionalLocale;
    final selected = await showDatePicker(
      context: context,
      locale: deviceLocale,
      initialDate: model.selectedRoastDate ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        model.selectedRoastDate = DateUtils.dateOnly(selected);
        model.roastDate.text = formatRegionalDate(selected, deviceLocale);
      });
    }
  }

  void _addOrigin() {
    setState(() => model.origins.add(CoffeeOriginDraft()));
  }

  void _removeOrigin(int index) {
    final removed = model.origins.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _moveOrigin(int index, int offset) {
    final nextIndex = index + offset;
    if (nextIndex < 0 || nextIndex >= model.origins.length) return;
    setState(() {
      final origin = model.origins.removeAt(index);
      model.origins.insert(nextIndex, origin);
    });
  }

  List<CoffeeComponentInput>? _originInputs() {
    final strings = AppLocalizations.of(context)!;
    final inputs = <CoffeeComponentInput>[];
    for (final origin in model.origins) {
      if (origin.isBlank) {
        if (origin.componentId != null) {
          showMessage(context, strings.emptyOriginMustBeRemoved);
          return null;
        }
        continue;
      }
      inputs.add(
        CoffeeComponentInput(
          id: origin.componentId,
          country: origin.country.text,
          region: origin.region.text,
          farm: origin.farm.text,
          producer: origin.producer.text,
          variety: origin.variety.text,
          process: origin.process.text,
          altitudeMeters: parseNumber(origin.altitude.text)?.round(),
          altitudeMaxMeters: parseNumber(origin.altitudeMax.text)?.round(),
          harvest: origin.harvest.text,
        ),
      );
    }
    return inputs;
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (model.saving || importingPhoto || model.photos.picking) return;
    if (!await validateAndReveal(formKey.currentState!) || !mounted) return;
    final originInputs = _originInputs();
    if (originInputs == null) return;
    try {
      final frozenLabel = await model.save(originInputs);
      if (mounted) FormExitGuard.complete(context, frozenLabel ?? true);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return FormExitGuard(
      hasChanges: () => model.changed,
      busy: () => model.saving || importingPhoto || model.photos.picking,
      child: SheetFrame(
        title: widget.existing == null ? s.newBean : s.editBean,
        formKey: formKey,
        saving: model.saving || importingPhoto || model.photos.picking,
        onSave: save,
        showScrollCue: true,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 20,
            children: [
              // The bag is what is in hand: its photo comes first.
              ..._photoFields(s),
              ..._identityFields(s),
              ..._inventoryFields(s),
              ..._detailsFields(s),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _identityFields(AppLocalizations s) => [
    SuggestedTextField(
      suggestions: suggestions?.names ?? const [],
      controller: model.name,
      maxLength: 200,
      decoration: InputDecoration(labelText: s.beanName, counterText: ''),
      validator: (value) =>
          value == null || value.trim().isEmpty ? s.requiredField : null,
    ),
    SuggestedTextField(
      suggestions: suggestions?.roasters ?? const [],
      controller: model.roaster,
      maxLength: 200,
      decoration: InputDecoration(labelText: s.roaster, counterText: ''),
    ),
    // Every level in sight, from lightest to darkest; tapping the chosen one
    // again clears it.
    InputDecorator(
      key: const ValueKey('coffee-roast-level'),
      decoration: InputDecoration(
        labelText: s.roastLevel,
        helperText: model.roastLevelChanged ? null : widget.roastLevelHint,
        border: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.only(top: 8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (code, label) in [
            ('ultra_light', s.roastUltraLight),
            ('light', s.roastLight),
            ('omni', s.roastOmni),
            ('medium', s.roastMedium),
            ('dark', s.roastDark),
          ])
            ChoiceChip(
              key: ValueKey('roast-level-$code'),
              label: Text(label),
              selected: model.roastLevel == code,
              onSelected: (selected) => setState(() {
                model.roastLevel = selected ? code : null;
                model.roastLevelChanged = true;
              }),
            ),
        ],
      ),
    ),
  ];

  List<Widget> _inventoryFields(AppLocalizations s) {
    final singleBag = widget.existing == null || widget.lots.length <= 1;
    final price = TextFormField(
      controller: model.paidPrice,
      inputFormatters: [decimalInputFormatter],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: s.paidPrice),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty || parsePriceCents(text) != null) return null;
        return s.invalidPrice;
      },
    );
    return [
      _originEditor(context, s),
      if (singleBag) ...[
        // Side by side only on wide screens: on a phone the date, its clear
        // button and the long labels need the full width.
        FieldPair(
          minimumRowWidth: 560,
          TextFormField(
            controller: model.roastDate,
            readOnly: true,
            onTap: chooseRoastDate,
            decoration: InputDecoration(
              labelText: s.roastDate,
              suffixIcon: IconButton(
                tooltip: model.roastDate.text.isEmpty
                    ? s.roastDate
                    : s.clearDate,
                onPressed: model.roastDate.text.isEmpty
                    ? chooseRoastDate
                    : () => setState(() {
                        model.selectedRoastDate = null;
                        model.roastDate.clear();
                      }),
                icon: Icon(
                  model.roastDate.text.isEmpty
                      ? Icons.calendar_today_outlined
                      : Icons.clear_rounded,
                ),
              ),
            ),
          ),
          TextFormField(
            key: const ValueKey('coffee-rest-days'),
            controller: model.restDays,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.restDays,
              helperText: s.restDaysHint,
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              final days = int.tryParse(text);
              return days == null || days < 0 || days > 365
                  ? s.invalidNumber
                  : null;
            },
          ),
        ),
        // What was bought and what it cost, read together.
        FieldPair(
          minimumRowWidth: 560,
          numberField(context, model.initialGrams, s.purchasedQuantity),
          price,
        ),
      ],
      if (widget.existing != null && widget.lots.length == 1)
        numberField(
          context,
          model.currentGrams,
          s.remainingQuantity,
          positive: false,
        ),
      if (widget.existing != null && widget.lots.isEmpty)
        Text(s.inventoryStartsFresh),
      if (widget.existing != null && widget.lots.length > 1)
        Text(s.inventoryMultiLotReadOnly),
      if (!singleBag) price,
      if (_pricePerKg case final pricePerKg?)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.pricePerKg),
          subtitle: Text(formatEuro(pricePerKg, regionalLocale.toString())),
        ),
    ];
  }

  List<Widget> _detailsFields(AppLocalizations s) => [
    FlavorNotesField(controller: model.flavorProfile),
    SwitchListTile.adaptive(
      key: const ValueKey('coffee-decaf'),
      contentPadding: EdgeInsets.zero,
      title: Text(s.decaf),
      value: model.isDecaf,
      onChanged: (value) => setState(() => model.isDecaf = value),
    ),
    TextFormField(
      key: const ValueKey('coffee-shop-url'),
      controller: model.shopUrl,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: s.shopUrl,
        hintText: s.shopUrlHint,
      ),
      validator: (value) {
        try {
          normalizeWebLink(value);
          return null;
        } on FormatException {
          return s.invalidWebLink;
        }
      },
    ),
    TextFormField(
      controller: model.notes,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 3,
      decoration: InputDecoration(labelText: s.notes),
    ),
    if (widget.existing == null) ..._freezeOnCreate(context, s),
  ];

  List<Widget> _photoFields(AppLocalizations s) => [
    if (widget.photos != null &&
        widget.importPhoto != null &&
        !catalogPhotoAdded)
      OutlinedButton.icon(
        key: const ValueKey('loffee-import-photo'),
        onPressed: importingPhoto || model.saving ? null : _importPhoto,
        icon: importingPhoto
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.image_outlined),
        label: Text(s.loffeeImportPhoto),
      ),
    if (widget.photos case final store?)
      PhotosField(store: store, draft: model.photos, label: s.bagPhoto),
  ];

  List<Widget> _freezeOnCreate(BuildContext context, AppLocalizations s) => [
    SwitchListTile.adaptive(
      key: const ValueKey('save-frozen-toggle'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.ac_unit_rounded),
      title: Text(s.saveFrozen),
      subtitle: Text(s.saveFrozenHint),
      value: model.saveFrozen,
      onChanged: (value) => setState(() {
        model.saveFrozen = value;
        if (value && model.frozenGrams.text.trim().isEmpty) {
          model.frozenGrams.text = model.initialGrams.text.trim();
        }
      }),
    ),
    if (model.saveFrozen) ...[
      TextFormField(
        key: const ValueKey('create-freeze-grams'),
        controller: model.frozenGrams,
        inputFormatters: [decimalInputFormatter],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: '${s.freezeAmount} (g)'),
        validator: (value) {
          final purchased = parseNumber(model.initialGrams.text);
          if (purchased == null || purchased <= 0) {
            return s.freezeNeedsQuantity;
          }
          final grams = parseNumber(value ?? '');
          if (grams == null || grams <= 0) return s.invalidNumber;
          if (grams > purchased + 1e-6) return s.notEnoughToFreeze;
          return null;
        },
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.container, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final code in JournalRepository.frozenContainers)
                ChoiceChip(
                  label: Text(frozenContainerLabel(s, code)),
                  selected: model.frozenContainer == code,
                  onSelected: (selected) => setState(
                    () => model.frozenContainer = selected ? code : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          key: const ValueKey('create-freeze-date'),
          tooltip: s.frozenDate,
          avatar: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            '${s.frozenDate}: ${formatRegionalDate(model.frozenDate, regionalLocale)}',
          ),
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              locale: regionalLocale,
              initialDate: model.frozenDate,
              firstDate: DateTime(1970),
              lastDate: DateTime(2100),
            );
            if (selected != null && mounted) {
              setState(() => model.frozenDate = selected);
            }
          },
        ),
      ),
      TextFormField(
        controller: model.frozenNotes,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 2,
        decoration: InputDecoration(labelText: s.frozenNotes),
      ),
    ],
  ];

  Widget _originEditor(BuildContext context, AppLocalizations strings) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.originDetails,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (var index = 0; index < model.origins.length; index++)
            CoffeeOriginCard(
              key: ValueKey('coffee-origin-card-${model.origins[index].key}'),
              origin: model.origins[index],
              suggestions: suggestions,
              index: index,
              onRemove: () => _removeOrigin(index),
              onChanged: () => setState(() {}),
              onMoveUp: index > 0 ? () => _moveOrigin(index, -1) : null,
              onMoveDown: index < model.origins.length - 1
                  ? () => _moveOrigin(index, 1)
                  : null,
            ),
          // After the origins, where the next one appears.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('add-coffee-origin'),
              onPressed: _addOrigin,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.addOrigin),
            ),
          ),
        ],
      );
}
