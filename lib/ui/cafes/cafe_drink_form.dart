import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_picker.dart';
import 'package:holybeans/ui/core/coffee_country_field.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';
import 'package:holybeans/ui/core/photos_draft.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/suggested_text_field.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

class CafeDrinkForm extends StatefulWidget {
  const CafeDrinkForm({
    super.key,
    required this.repository,
    required this.data,
    this.existing,
    this.photos,
  });
  final CafeRepository repository;
  final CafeJournalData data;
  final CafeDrink? existing;
  final PhotoStore? photos;
  @override
  State<CafeDrinkForm> createState() => _CafeDrinkFormState();
}

class _CafeDrinkFormState extends State<CafeDrinkForm> {
  final form = GlobalKey<FormState>();
  final originFocus = FocusNode();
  final fields = <String, TextEditingController>{};
  late final PhotosDraft photos;
  late DateTime date;
  late String initial;
  CafeInput? venue;
  bool saving = false;
  TextEditingController field(String key) => fields[key]!;
  String text(String key) => field(key).text.trim();
  String snapshot() =>
      '${fields.values.map((c) => c.text).toList()}|${date.toIso8601String()}|${venue?.id}|${venue?.sourceKey}';
  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    final c = d == null ? null : widget.data.cafeOf(d);
    venue = c == null
        ? null
        : CafeInput(
            id: c.id,
            name: c.name,
            country: c.country,
            city: c.city,
            address: c.address,
            latitude: c.latitude,
            longitude: c.longitude,
            sourceKey: c.sourceKey,
            sourceUrl: c.sourceUrl,
          );
    final values = {
      'venue': c?.name,
      'city': c?.city,
      'country': c?.country,
      'address': c?.address,
      'type': d?.drinkType,
      'roaster': d == null ? null : widget.data.roasterOf(d),
      'coffee': d?.coffeeName,
      'origin': d?.originCountry,
      'process': d?.process,
      'variety': d?.variety,
      'notes': d?.notes,
      'rating': d?.rating?.toString(),
      'price': d?.priceCents == null
          ? null
          : (d!.priceCents! / 100).toStringAsFixed(2),
      'currency': d?.currency ?? 'EUR',
    };
    for (final e in values.entries) {
      fields[e.key] = TextEditingController(text: e.value ?? '');
    }
    date = d == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(d.drankAtMs);
    photos = PhotosDraft(
      widget.photos,
      d == null ? [] : widget.data.photosOf(d.id),
    );
    photos.deletePhoto = (name) =>
        widget.repository.deletePhotoIfUnused(widget.photos, name);
    initial = snapshot();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    photos.dispose();
    originFocus.dispose();
    super.dispose();
  }

  Future<void> chooseVenue() async {
    final selected = await Navigator.of(context).push<CafeInput>(
      MaterialPageRoute(builder: (_) => CafePicker(data: widget.data)),
    );
    if (!mounted || selected == null) return;
    setState(() {
      venue = selected;
      field('venue').text = selected.name;
      field('city').text = selected.city ?? '';
      field('country').text = selected.country ?? '';
      field('address').text = selected.address ?? '';
    });
  }

  Future<void> save(BuildContext guardedContext) async {
    if (saving || photos.picking || !form.currentState!.validate()) return;
    setState(() => saving = true);
    photos.beginSave();
    try {
      // Editing a selected venue's name creates a manual venue, preserving the
      // identity of the original place and all other visits to it.
      final sameVenue = text('venue') == venue?.name;
      await widget.repository.save(
        CafeDrinkInput(
          id: widget.existing?.id,
          cafe: CafeInput(
            id: sameVenue ? venue?.id : null,
            name: text('venue'),
            country: text('country'),
            city: text('city'),
            address: text('address'),
            latitude: sameVenue ? venue?.latitude : null,
            longitude: sameVenue ? venue?.longitude : null,
            sourceKey: sameVenue ? venue?.sourceKey : null,
            sourceUrl: sameVenue ? venue?.sourceUrl : null,
          ),
          drinkType: text('type'),
          drankAt: date,
          roaster: text('roaster'),
          coffeeName: text('coffee'),
          originCountry: text('origin'),
          process: text('process'),
          variety: text('variety'),
          notes: text('notes'),
          rating: number('rating'),
          priceCents: number('price') == null
              ? null
              : (number('price')! * 100).round(),
          currency: text('currency').toUpperCase(),
          photos: photos.current,
        ),
      );
      await photos.commit();
      if (guardedContext.mounted) FormExitGuard.complete(guardedContext, true);
    } catch (error, stack) {
      reportError(error, stack);
      photos.endSave();
      if (mounted) {
        setState(() => saving = false);
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    }
  }

  double? number(String key) => double.tryParse(text(key).replaceAll(',', '.'));
  Widget input(
    String key,
    String label, {
    bool required = false,
    bool numeric = false,
    int? max,
    List<String>? suggestions,
  }) {
    final s = AppLocalizations.of(context)!;
    String? validate(String? value) {
      if (required && (value ?? '').trim().isEmpty) return s.cafeRequired;
      if (numeric &&
          text(key).isNotEmpty &&
          (number(key) == null ||
              !number(key)!.isFinite ||
              number(key)! < 0 ||
              (key == 'rating' && number(key)! > 10))) {
        return s.cafeInvalidNumber;
      }
      if (key == 'currency' &&
          !RegExp(r'^[A-Z]{3}$').hasMatch(text(key).toUpperCase())) {
        return s.cafeInvalidNumber;
      }
      return null;
    }

    final decoration = InputDecoration(labelText: label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: suggestions == null
          ? TextFormField(
              key: ValueKey('cafe-$key'),
              controller: field(key),
              decoration: decoration,
              validator: validate,
              maxLength: max,
              minLines: key == 'notes' ? 2 : 1,
              maxLines: key == 'notes' ? 5 : 1,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            )
          : SuggestedTextField(
              fieldKey: ValueKey('cafe-$key'),
              controller: field(key),
              decoration: decoration,
              validator: validate,
              suggestions: suggestions,
              maxLength: max,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return FormExitGuard(
      hasChanges: () => snapshot() != initial || photos.changed,
      busy: () => saving || photos.picking,
      child: Builder(
        builder: (guarded) => Scaffold(
          appBar: AppBar(
            title: Text(
              widget.existing == null ? s.cafeAddDrink : s.cafeEditDrink,
            ),
            leading: BackButton(onPressed: () => FormExitGuard.cancel(guarded)),
          ),
          body: SafeArea(
            child: Form(
              key: form,
              child: AbsorbPointer(
                absorbing: saving,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: chooseVenue,
                        icon: const Icon(Icons.search),
                        label: Text(s.cafeChooseVenue),
                      ),
                      const SizedBox(height: 12),
                      input('venue', s.cafeVenue, required: true, max: 200),
                      input('city', s.cafeCity),
                      input('country', s.cafeVenueCountry),
                      input('address', s.cafeAddress),
                      input(
                        'type',
                        s.cafeDrinkType,
                        required: true,
                        max: 120,
                        suggestions: s.cafeDrinkSuggestions.split(';'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.date),
                        subtitle: Text(
                          formatRegionalDate(date, regionalLocale),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final selected = await showDatePicker(
                            context: context,
                            locale: regionalLocale,
                            initialDate: date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (!mounted || selected == null) return;
                          setState(
                            () => date = DateTime(
                              selected.year,
                              selected.month,
                              selected.day,
                              date.hour,
                              date.minute,
                            ),
                          );
                        },
                      ),
                      input(
                        'roaster',
                        s.roaster,
                        max: 200,
                        suggestions: widget.data.roasters
                            .map((r) => r.name)
                            .toList(),
                      ),
                      input('coffee', s.cafeCoffeeName),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: CoffeeCountryField(
                          controller: field('origin'),
                          focusNode: originFocus,
                          label: s.cafeOriginCountry,
                          fieldKey: const ValueKey('cafe-origin'),
                        ),
                      ),
                      input('process', s.process),
                      input('variety', s.variety),
                      input('rating', '${s.rating} (0–10)', numeric: true),
                      input('price', s.cafePrice, numeric: true),
                      input('currency', s.cafeCurrency, required: true, max: 3),
                      input('notes', s.notes),
                      if (widget.photos != null)
                        ListenableBuilder(
                          listenable: photos,
                          builder: (_, _) => PhotosField(
                            store: widget.photos!,
                            draft: photos,
                            label: s.photos,
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('cafe-save'),
                        onPressed: saving ? null : () => save(guarded),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
