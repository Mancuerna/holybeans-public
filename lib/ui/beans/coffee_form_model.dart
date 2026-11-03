import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/ui/beans/coffee_origin_draft.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/photos_draft.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Owns the editable coffee draft and coordinates its complete save.
class CoffeeFormModel extends ChangeNotifier {
  CoffeeFormModel({
    required this.repository,
    this.existing,
    this.card,
    this.initialNotes,
    this.components = const [],
    this.lots = const [],
    PhotoStore? photoStore,
    List<String> savedPhotos = const [],
  }) : photos = PhotosDraft(photoStore, savedPhotos) {
    photos.addListener(_notify);
    final storedRoastDate = lots.length == 1
        ? lots.single.roastDate
        : card?.roastDate;
    selectedRoastDate = DateTime.tryParse(storedRoastDate ?? '');
    _initialState = fingerprint;
  }

  final JournalRepository repository;
  final Coffee? existing;
  final SharedBean? card;
  final String? initialNotes;
  final List<CoffeeComponent> components;
  final List<CoffeeLot> lots;
  final PhotosDraft photos;
  bool saving = false;
  bool _disposed = false;

  late final name = TextEditingController(text: existing?.name ?? card?.name);
  late final roaster = TextEditingController(
    text: existing?.roaster ?? card?.roaster,
  );
  late final notes = TextEditingController(
    text: existing?.notes ?? initialNotes,
  );
  late final flavorProfile = TextEditingController(
    text: existing?.flavorProfile ?? card?.flavorProfile,
  );
  late bool isDecaf = existing?.isDecaf ?? card?.decaf ?? false;
  late final shopUrl = TextEditingController(
    text: existing?.shopUrl ?? card?.shopUrl,
  );
  late final List<CoffeeOriginDraft> origins = switch (card) {
    final card? when existing == null =>
      card.origins.map(CoffeeOriginDraft.fromCard).toList(),
    _ => components.map(CoffeeOriginDraft.fromComponent).toList(),
  };
  late final roastDate = TextEditingController();
  DateTime? selectedRoastDate;
  late String? roastLevel = existing?.roastLevel ?? card?.roastLevel;
  bool roastLevelChanged = false;
  late final restDays = TextEditingController(
    text: existing?.restDays?.toString(),
  );
  late final initialGrams = TextEditingController(
    text: lots.length == 1
        ? _initialNumber(lots.single.initialGrams)
        : _initialNumber(card?.bagGrams),
  );
  late final currentGrams = TextEditingController(
    text: lots.length == 1 ? _initialNumber(lots.single.remainingGrams) : null,
  );
  bool saveFrozen = false;
  final frozenGrams = TextEditingController();
  final frozenNotes = TextEditingController();
  String? frozenContainer;
  DateTime frozenDate = DateTime.now();
  late final paidPrice = TextEditingController(
    text: _priceText(existing?.paidPriceCents ?? card?.priceCents),
  );
  late final String _initialState;
  bool get changed => fingerprint != _initialState;

  String get fingerprint => jsonEncode([
    for (final field in [
      name,
      roaster,
      notes,
      flavorProfile,
      shopUrl,
      restDays,
      initialGrams,
      currentGrams,
      paidPrice,
      frozenGrams,
      frozenNotes,
    ])
      field.text,
    selectedRoastDate == null
        ? null
        : formatIsoCalendarDate(selectedRoastDate!),
    roastLevel,
    isDecaf,
    saveFrozen,
    frozenContainer,
    formatIsoCalendarDate(frozenDate),
    photos.current,
    for (final origin in origins)
      [
        origin.componentId,
        for (final field in [
          origin.country,
          origin.region,
          origin.farm,
          origin.producer,
          origin.variety,
          origin.process,
          origin.altitude,
          origin.altitudeMax,
          origin.harvest,
        ])
          field.text,
      ],
  ]);

  static String _initialNumber(double? value) =>
      value == null ? '' : fieldExact(value);

  static String _priceText(int? cents) => cents == null
      ? ''
      : fieldDecimal(
          '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}',
        );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<String?> save(List<CoffeeComponentInput> originInputs) async {
    if (saving || photos.picking || photos.locked) {
      throw StateError('Coffee draft is busy');
    }
    if (paidPrice.text.trim().isNotEmpty &&
        parsePriceCents(paidPrice.text) == null) {
      throw const FormatException('Invalid coffee price');
    }
    photos.beginSave();
    saving = true;
    _notify();
    try {
      if (existing case final coffee?) {
        final updateRemainingStock =
            lots.length == 1 &&
            parseNumber(currentGrams.text) != lots.single.remainingGrams;
        await repository.updateCoffeeProfileWithComponents(
          id: coffee.id,
          name: name.text,
          roaster: roaster.text,
          notes: notes.text,
          paidPriceCents: parsePriceCents(paidPrice.text),
          components: originInputs,
          roastLevel: roastLevel,
          updateRoastLevel: true,
          restDays: int.tryParse(restDays.text.trim()),
          updateRestDays: true,
          flavorProfile: flavorProfile.text,
          updateFlavorProfile: true,
          inventoryLotId: lots.length == 1 ? lots.single.id : null,
          createInventoryLot: lots.isEmpty,
          roastDate: lots.length <= 1
              ? (selectedRoastDate == null
                    ? null
                    : formatIsoCalendarDate(selectedRoastDate!))
              : null,
          initialGrams: lots.length <= 1
              ? parseNumber(initialGrams.text)
              : null,
          remainingGrams: updateRemainingStock
              ? parseNumber(currentGrams.text)
              : null,
          updateRemainingStock: updateRemainingStock,
          isDecaf: isDecaf,
          shopUrl: shopUrl.text,
          photos: photos.changed ? photos.current : null,
        );
        await photos.commit();
      } else {
        final created = await repository.createCoffeeEntry(
          name: name.text,
          isDecaf: isDecaf,
          shopUrl: shopUrl.text,
          photos: photos.changed ? photos.current : null,
          roaster: roaster.text,
          components: originInputs,
          notes: notes.text,
          roastDate: roastDate.text.trim().isEmpty
              ? null
              : formatIsoCalendarDate(selectedRoastDate!),
          initialGrams: parseNumber(initialGrams.text),
          paidPriceCents: parsePriceCents(paidPrice.text),
          roastLevel: roastLevel,
          restDays: int.tryParse(restDays.text.trim()),
          flavorProfile: flavorProfile.text,
          freeze: saveFrozen
              ? FreezeRequest(
                  grams: parseNumber(frozenGrams.text)!,
                  frozenDate: formatIsoCalendarDate(frozenDate),
                  container: frozenContainer,
                  notes: frozenNotes.text,
                )
              : null,
        );
        await photos.commit();
        return created.frozenLabel;
      }
      return null;
    } finally {
      photos.endSave();
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final field in [
      name,
      roaster,
      notes,
      flavorProfile,
      shopUrl,
      roastDate,
      restDays,
      initialGrams,
      currentGrams,
      paidPrice,
      frozenGrams,
      frozenNotes,
    ]) {
      field.dispose();
    }
    for (final origin in origins) {
      origin.dispose();
    }
    photos.dispose();
    super.dispose();
  }
}
