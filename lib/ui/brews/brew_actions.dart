import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/share_brew_flow.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart' show formatGrams;
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Brew flows used by the shell's JournalActions implementation.
class BrewActions {
  BrewActions({
    required this.context,
    required this.repository,
    required this.parameterSettings,
    required this.templateSettings,
    required this.reminderSettings,
    required this.methods,
    required this.message,
    required this.showBeans,
    required this.confirmArchive,
    this.photos,
    this.scale,
    this.pressureSensor,
    this.refractometer,
    this.reminders,
  });

  final BuildContext context;
  final JournalRepository repository;
  final BrewParameterSettings parameterSettings;
  final ShareTemplateSettings templateSettings;
  final RateReminderSettings reminderSettings;
  final List<BrewMethod> Function() methods;
  final void Function(String) message;
  final void Function() showBeans;
  final Future<bool> Function(Coffee, bool, String?) confirmArchive;
  final PhotoStore? photos;
  final Scale? scale;
  final PressureSensor? pressureSensor;
  final Refractometer? refractometer;
  final RateReminders? reminders;
  final _stockArchiveOffered = <String>{};

  Future<void> openBrewForm(
    List<Coffee> coffees, {
    Brew? existing,
    Brew? seed,
    String? initialCoffeeId,
    String? initialLotId,
    double? initialDoseGrams,
    FrozenBrewSource? initialFrozenSource,
    String? initialMethodId,
    bool repeat = false,
    bool adjust = false,
  }) async {
    try {
      if (existing != null) {
        existing = await repository.brew(existing.id) ?? existing;
      }
      if (seed != null) seed = await repository.brew(seed.id) ?? seed;
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) message(AppLocalizations.of(context)!.dataError);
      return;
    }
    if (!context.mounted) return;
    final s = AppLocalizations.of(context)!;
    final available = coffees
        .where(
          (coffee) =>
              coffee.archivedAtMs == null ||
              (existing != null && coffee.id == existing.coffeeId),
        )
        .toList();
    if (available.isEmpty) {
      message(s.needBean);
      showBeans();
      return;
    }
    final savedPhotos = existing == null
        ? const <String>[]
        : await repository.brewPhotos(existing.id);
    if (!context.mounted) return;
    final result = await showFormSheet<BrewFormResult>(
      context,
      BrewForm(
        savedPhotos: savedPhotos,
        photos: photos,
        repository: repository,
        settings: parameterSettings,
        coffees: available,
        existing: existing,
        seed: seed,
        initialCoffeeId: initialCoffeeId,
        initialLotId: initialLotId,
        initialDoseGrams: initialDoseGrams,
        initialFrozenSource: initialFrozenSource,
        initialMethodId: initialMethodId,
        repeat: repeat,
        adjust: adjust,
        scale: scale,
        pressureSensor: pressureSensor,
        refractometer: refractometer,
      ),
    );
    if (result != null && context.mounted) {
      if (existing == null && !result.rated) {
        // The rating comes when the cup is drunk: the notice offers it.
        _offerRating(result.brewId, available, s);
      } else {
        message(existing == null ? s.brewSaved : s.brewUpdated);
      }
      if (existing == null && !result.rated) {
        await _scheduleRateReminder(result.brewId, result.coffeeId, coffees);
      }
      if (result.overdrawIncreased) {
        final coffee = available
            .where((row) => row.id == result.coffeeId)
            .firstOrNull;
        if (coffee != null) {
          _stockArchiveOffered.add(coffee.id);
          await confirmArchive(coffee, true, null);
        }
      } else if (existing == null &&
          !_stockArchiveOffered.contains(result.coffeeId)) {
        final suggestion = await repository.archiveSuggestionForBrew(
          result.brewId,
        );
        if (suggestion != null && context.mounted) {
          _stockArchiveOffered.add(result.coffeeId);
          await confirmArchive(
            suggestion.coffee,
            false,
            s.archiveBeanForLowStock(
              formatGrams(suggestion.remainingGrams, regionalLocale.toString()),
              formatGrams(suggestion.meanDose, regionalLocale.toString()),
              suggestion.methodName,
            ),
          );
        }
      }
    }
  }

  Future<void> shareBrew(
    Brew brew,
    Coffee coffee,
    List<CoffeeComponent> components,
  ) async {
    try {
      brew = await repository.brew(brew.id) ?? brew;
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) message(AppLocalizations.of(context)!.dataError);
      return;
    }
    if (!context.mounted) return;
    await shareBrewFlow(
      context,
      photos: photos,
      repository: repository,
      settings: parameterSettings,
      templateSettings: templateSettings,
      brew: brew,
      coffee: coffee,
      components: components,
      method: methods().where((row) => row.id == brew.methodId).firstOrNull,
      message: message,
    );
  }

  Future<void> _scheduleRateReminder(
    String brewId,
    String coffeeId,
    List<Coffee> coffees,
  ) async {
    final reminders = this.reminders;
    if (reminders == null) return;
    final s = AppLocalizations.of(context)!;
    try {
      final minutes = await reminderSettings.loadMinutes();
      if (minutes == null) return;
      final coffee = coffees.where((row) => row.id == coffeeId).firstOrNull;
      await reminders.schedule(
        brewId: brewId,
        after: Duration(minutes: minutes),
        title: s.rateReminderTitle,
        body: s.rateReminderBody(coffee?.name ?? ''),
      );
    } catch (error, stack) {
      reportError(error, stack);
      // A reminder is a convenience; saving the brew already succeeded.
    }
  }

  /// "Brew saved" with a Rate action that opens the rating sheet.
  void _offerRating(String brewId, List<Coffee> coffees, AppLocalizations s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('brew-saved-rate-later'),
        content: Text(s.brewSaved),
        duration: const Duration(seconds: 8),
        // With an action a snack bar would stay until dismissed.
        persist: false,
        action: SnackBarAction(
          label: s.rateBrew,
          onPressed: () async {
            final brew = await repository.brew(brewId);
            if (brew == null || !context.mounted) return;
            await rateBrew(
              brew,
              coffees.where((c) => c.id == brew.coffeeId).firstOrNull,
            );
          },
        ),
      ),
    );
  }

  Future<void> rateBrew(Brew brew, Coffee? coffee) async {
    try {
      brew = await repository.brew(brew.id) ?? brew;
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) message(AppLocalizations.of(context)!.dataError);
      return;
    }
    if (!context.mounted) return;
    final saved = await showRateBrewSheet(
      context,
      repository,
      brew,
      title: [coffee?.name ?? '—', brew.methodName].join(', '),
    );
    if (saved == true) {
      await reminders?.cancel(brew.id);
      if (context.mounted) message(AppLocalizations.of(context)!.brewRated);
    }
  }

  Future<void> archiveBrew(Brew brew) async {
    final s = AppLocalizations.of(context)!;
    try {
      await repository.setBrewArchived(
        brew.id,
        archived: brew.archivedAtMs == null,
      );
    } on BrewArchivedWithCoffeeException {
      message(s.restoreCoffeeFirst);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  Future<bool> setBrewFavorite(
    Brew brew, {
    required bool favorite,
    bool announce = true,
  }) async {
    final s = AppLocalizations.of(context)!;
    try {
      await repository.setBrewFavorite(brew.id, favorite: favorite);
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.saveFailed);
      return false;
    }
    if (announce && context.mounted) {
      message(
        favorite
            ? s.favoriteRecipeSet(brew.methodName)
            : s.favoriteRecipeRemoved,
      );
    }
    return true;
  }
}
