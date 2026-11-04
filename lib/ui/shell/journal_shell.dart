import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/freshness_calendar_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/app_shortcut.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_actions.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/backup/backup_section.dart';
import 'package:holybeans/ui/beans/archive_dialog.dart';
import 'package:holybeans/ui/beans/bean_add_button.dart';
import 'package:holybeans/ui/beans/bean_import.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/beans/freshness_calendar_page.dart';
import 'package:holybeans/ui/beans/loffee_import.dart';
import 'package:holybeans/ui/beans/loffee_key_dialog.dart';
import 'package:holybeans/ui/brews/brew_actions.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/brew_comparison_picker.dart';
import 'package:holybeans/ui/brews/brew_details_sheet.dart';
import 'package:holybeans/ui/brews/history_filters.dart';
import 'package:holybeans/ui/brews/history_tab.dart';
import 'package:holybeans/ui/brews/share_template_exchange.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/cafes/cafes_page.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/lazy_indexed_stack.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/smooth_floating_button.dart';
import 'package:holybeans/ui/equipment/equipment_forms.dart';
import 'package:holybeans/ui/equipment/equipment_page.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';
import 'package:holybeans/ui/equipment/tool_form.dart';
import 'package:holybeans/ui/equipment/water_profile_form.dart';
import 'package:holybeans/ui/home/home_tab.dart';
import 'package:holybeans/ui/roasters/roaster_routes.dart';
import 'package:holybeans/ui/settings/beanconqueror_import_page.dart';
import 'package:holybeans/ui/settings/pours_from_curves.dart';
import 'package:holybeans/ui/settings/settings_page.dart';
import 'package:holybeans/ui/shell/floating_button_state.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_app_bar.dart';
import 'package:holybeans/ui/shell/journal_navigation_bar.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';
import 'package:holybeans/ui/shell/system_surfaces.dart';
import 'package:holybeans/ui/stats/live_stats_page.dart';

/// The app's main screen: navigation between Home, Beans, History and
/// Equipment, the floating action, and the [JournalActions] the tabs use.
class JournalShell extends StatefulWidget {
  const JournalShell({
    super.key,
    required this.database,
    this.locale,
    required this.onLocaleChanged,
    this.photos,
    this.reminders,
    this.openRate,
    this.scale,
    this.pressureSensor,
    this.refractometer,
    this.exportFolder,
    this.incoming,
    this.loffee,
    this.backupServices,
    this.driveTile,
  });

  final AppDatabase database;
  final PhotoStore? photos;
  final Widget? driveTile;

  /// Automatic and folder copies; without them only manual backups remain.
  final BackupServices? backupServices;
  final RateReminders? reminders;

  /// Bluetooth scale; without it the scale controls are hidden.
  final Scale? scale;

  /// Bluetooth pressure sensor; without it its controls are hidden.
  final PressureSensor? pressureSensor;

  /// Bluetooth refractometer; without it the TDS has no measure button.
  final Refractometer? refractometer;

  /// Reads another app's export folder; without it imports take a file.
  final ExportFolder? exportFolder;

  /// Coffee cards opened, shared or scanned into the app.
  final IncomingShares? incoming;
  final LoffeeServices? loffee;
  final ValueNotifier<String?>? openRate;

  /// The explicitly chosen app locale, or null when following the system.
  final Locale? locale;
  final ValueChanged<Locale?> onLocaleChanged;

  @override
  State<JournalShell> createState() => _JournalShellState();
}

class _JournalShellState extends State<JournalShell>
    with SingleTickerProviderStateMixin
    implements JournalActions {
  @override
  late final JournalRepository repository = JournalRepository(widget.database);

  @override
  PhotoStore? get photos => widget.photos;

  @override
  late final BackupCenter backupCenter = BackupCenter(
    database: widget.database,
    photos: widget.photos,
    services: widget.backupServices,
  );
  late final BackupActions backups = BackupActions(
    center: backupCenter,
    repository: repository,
    photos: widget.photos,
    message: message,
  );
  late final BrewParameterSettings parameterSettings = BrewParameterSettings(
    widget.database,
  );
  late final RateReminderSettings reminderSettings = RateReminderSettings(
    widget.database,
  );

  /// The live journal and the settings the tabs follow.
  late final JournalViewModel journal = JournalViewModel(
    repository: repository,
    parameterSettings: parameterSettings,
    listOptionsSettings: ListOptionsSettings(widget.database),
  );
  late final templateSettings = ShareTemplateSettings(widget.database);
  late final brewActions = BrewActions(
    context: context,
    repository: repository,
    parameterSettings: parameterSettings,
    templateSettings: templateSettings,
    reminderSettings: reminderSettings,
    methods: () => methods,
    message: message,
    showBeans: () => setState(() => tab = 1),
    confirmArchive: (coffee, afterOverdraw, reason) => confirmCoffeeArchive(
      coffee,
      afterOverdraw: afterOverdraw,
      reason: reason,
    ),
    photos: widget.photos,
    scale: widget.scale,
    pressureSensor: widget.pressureSensor,
    refractometer: widget.refractometer,
    reminders: widget.reminders,
  );
  late final TabController beanTabs = TabController(length: 3, vsync: this);
  final historyFilters = HistoryFilters();
  final floatingExtension = FloatingButtonExtension();
  late final surfaces = SystemSurfaces(
    journal: journal,
    describe: (brew) => (
      journal.coffees
          .where((coffee) => coffee.id == brew.coffeeId)
          .firstOrNull
          ?.name,
      brewRecipeParts(
        brew,
        journal.methods,
        regionalLocale.toString(),
        hidden: hiddenParameters,
      ).join('  '),
    ),
  );
  int _tab = 0;
  int get tab => _tab;

  /// Changing tab unfolds the floating button that scrolling folded.
  set tab(int value) {
    if (value != _tab) floatingExtension.reset();
    _tab = value;
  }

  EquipmentSection equipmentSection = EquipmentSection.methods;
  bool showArchivedEquipment = false;

  @override
  List<BrewMethod> get methods => journal.methods;

  @override
  List<FrozenPortion> get portions => journal.portions;

  @override
  Set<BrewParameter> get hiddenParameters => journal.hiddenParameters;

  @override
  List<CoffeeLot> get latestLots => journal.lots;

  @override
  FreshnessToday? freshnessToday(Coffee coffee, {BrewStyle? style}) =>
      journal.freshnessOf(coffee, style: style);

  @override
  void initState() {
    super.initState();
    unawaited(
      journal.loadListOptions().then((options) {
        if (!mounted) return;
        historyFilters.update(
          () => historyFilters.showArchived = options.showArchivedBrews,
        );
      }),
    );
    widget.openRate?.addListener(_openRateFromReminder);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openRateFromReminder(),
    );
    backupCenter.start();
    surfaces.start();
    if (widget.incoming case final incoming?) {
      _arrivals = incoming.arrivals.listen(_receiveCard);
      unawaited(
        incoming.takeLaunch().then((text) {
          if (text != null && text.trim().isNotEmpty) {
            unawaited(_receiveCard(text));
          }
        }),
      );
    }
  }

  StreamSubscription<String>? _arrivals;

  /// Imports a card that reached the app, once the journal has loaded so
  /// that a coffee already there is recognised.
  Future<void> _receiveCard(String text) async {
    while (journal.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (!mounted) return;
    if (AppShortcut.fromLink(text) case final shortcut?) {
      await runAppShortcut(
        context,
        shortcut,
        actions: this,
        journal: journal,
        incoming: widget.incoming,
      );
    } else if (isShareTemplateFile(text)) {
      final settings = templateSettings;
      final imported = await importShareTemplate(
        context,
        settings,
        source: text,
      );
      if (imported != null && mounted) {
        message(AppLocalizations.of(context)!.shareTemplateSaved);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ShareTemplatesPage(settings: settings, style: imported.style),
          ),
        );
      }
    } else {
      await importBeansFromText(context, this, journal.coffees, text);
    }
  }

  @override
  Future<void> addCoffeeFromCard(SharedBean card) async {
    final saved = await showFormSheet<Object>(
      context,
      CoffeeForm(repository: repository, photos: widget.photos, card: card),
    );
    if (saved != null && mounted) {
      message(AppLocalizations.of(context)!.beanSaved);
    }
  }

  @override
  void showCoffeeDetailsById(String id) {
    final coffee = journal.coffees.where((row) => row.id == id).firstOrNull;
    if (coffee != null) showCoffeeDetails(coffee, journal.data);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Shortcuts, widget and notice follow the app's language.
    surfaces.relabel(surfaceLabels(AppLocalizations.of(context)!));
  }

  @override
  void dispose() {
    historyFilters.dispose();
    unawaited(_arrivals?.cancel());
    journal.dispose();
    backupCenter.dispose();
    widget.openRate?.removeListener(_openRateFromReminder);
    beanTabs.dispose();
    floatingExtension.dispose();
    surfaces.dispose();
    super.dispose();
  }

  @override
  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Future<void> addCoffee([Coffee? existing]) async {
    final components = existing == null
        ? <CoffeeComponent>[]
        : await repository.coffeeComponents(existing.id);
    final lots = existing == null
        ? <CoffeeLot>[]
        : await repository.coffeeLots(existing.id);
    final savedPhotos = existing == null
        ? const <String>[]
        : await repository.coffeePhotos(existing.id);
    if (!mounted) return;
    // The form returns true, or the frozen portion's label when the new
    // coffee went straight into the freezer.
    final saved = await showFormSheet<Object>(
      context,
      CoffeeForm(
        repository: repository,
        existing: existing,
        components: components,
        lots: lots,
        photos: widget.photos,
        savedPhotos: savedPhotos,
      ),
    );
    if (saved is String && mounted) {
      message(AppLocalizations.of(context)!.frozenSaved(saved));
    } else if (saved == true && mounted) {
      message(AppLocalizations.of(context)!.beanSaved);
    }
  }

  Future<void> addMethod() async {
    final saved = await showMethodForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context)!.methodSaved);
    }
  }

  Future<void> addGrinder() async {
    final saved = await showGrinderForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context)!.grinderSaved);
    }
  }

  @override
  Future<void> exportBackup() => backups.exportBackup(context);

  @override
  Future<void> saveBackupToFolder() => backups.saveToFolder(context);

  @override
  Future<void> chooseBackupFolder() => backups.chooseFolder(context);

  Future<void> addWaterProfile() async {
    final saved = await showWaterProfileForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context)!.waterProfileSaved);
    }
  }

  Future<void> _importBeanconqueror() async {
    final summary = await importFromBeanconqueror(
      context,
      repository: repository,
      photos: widget.photos,
      folder: widget.exportFolder,
    );
    if (summary == null || !mounted) return;
    message(bqSummaryMessage(AppLocalizations.of(context)!, summary));
  }

  void openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          locale: widget.locale,
          onLocaleChanged: widget.onLocaleChanged,
          onExportBackup: exportBackup,
          onExportCsv: () => backups.exportBrewsCsv(context),
          onImportBackup: () => backups.importBackup(context),
          backupTiles: Column(
            children: [
              BackupSection(
                center: backupCenter,
                actions: backups,
                onSaveToFolder: saveBackupToFolder,
                onChooseFolder: chooseBackupFolder,
              ),
              ?widget.driveTile,
            ],
          ),
          onImportBeanconqueror: _importBeanconqueror,
          onConfigureLoffee: widget.loffee == null
              ? null
              : () => configureLoffeeKey(context, widget.loffee!.keys),
          onFillPoursFromCurves: () => fillPoursFromCurves(
            context,
            repository: repository,
            message: message,
          ),
          parameterSettings: parameterSettings,
          templateSettings: templateSettings,
          reminders: widget.reminders,
          reminderSettings: reminderSettings,
          scale: widget.scale,
          pressureSensor: widget.pressureSensor,
          refractometer: widget.refractometer,
        ),
      ),
    );
  }

  void openStats(
    List<Coffee> coffees,
    List<Brew> brews,
    List<CoffeeLot> lots,
    List<CoffeeComponent> components,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LiveStatsPage(
        actions: this,
        coffees: coffees,
        brews: brews,
        lots: lots,
        components: components,
      ),
    ),
  );

  @override
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
  }) => brewActions.openBrewForm(
    coffees,
    existing: existing,
    seed: seed,
    initialCoffeeId: initialCoffeeId,
    initialLotId: initialLotId,
    initialDoseGrams: initialDoseGrams,
    initialFrozenSource: initialFrozenSource,
    initialMethodId: initialMethodId,
    repeat: repeat,
    adjust: adjust,
  );

  @override
  Future<void> shareBrew(
    Brew brew,
    Coffee coffee,
    List<CoffeeComponent> components,
  ) => brewActions.shareBrew(brew, coffee, components);

  /// Opens the rate sheet for a brew whose reminder was tapped.
  Future<void> _openRateFromReminder() async {
    final brewId = widget.openRate?.value;
    if (brewId == null || !mounted) return;
    widget.openRate!.value = null;
    final brew = await repository.brew(brewId);
    if (brew == null || !mounted) return;
    final coffee = await repository.coffee(brew.coffeeId);
    if (!mounted) return;
    await rateBrew(brew, coffee);
  }

  @override
  Future<void> rateBrew(Brew brew, Coffee? coffee) =>
      brewActions.rateBrew(brew, coffee);

  @override
  Future<void> archiveBrew(Brew brew) => brewActions.archiveBrew(brew);

  @override
  Future<bool> setBrewFavorite(
    Brew brew, {
    required bool favorite,
    bool announce = true,
  }) =>
      brewActions.setBrewFavorite(brew, favorite: favorite, announce: announce);

  @override
  void showCoffeeDetails(Coffee coffee, JournalData data) =>
      showCoffeeDetailsSheet(context, this, coffee, data);

  @override
  void showBrewDetails(Brew brew, Coffee? coffee, JournalData data) =>
      showBrewDetailsSheet(context, this, brew, coffee, data);

  @override
  Future<void> compareBrew(Brew brew, JournalData data) =>
      showBrewComparison(context, this, brew, data);

  @override
  void showAllBeans() => setState(() {
    tab = 1;
    beanTabs.index = 0;
  });

  @override
  void showBrewsOfCoffee(Coffee coffee) {
    // Every brew of the coffee, archived ones too, as its details count
    // them.
    historyFilters.update(() {
      historyFilters.resetForNavigation();
      historyFilters.coffeeId = coffee.id;
      historyFilters.showArchived = true;
    });
    setState(() => tab = 2);
  }

  @override
  Future<bool> confirmCoffeeArchive(
    Coffee coffee, {
    bool afterOverdraw = false,
    String? reason,
  }) async {
    final ratings = [
      for (final brew in await repository.brewsOfCoffee(coffee.id))
        ?brew.rating,
    ];
    if (!mounted) return false;
    final decision = await showDialog<CoffeeArchiveDecision>(
      context: context,
      builder: (_) => CoffeeArchiveDialog(
        coffeeName: coffee.name,
        initialRating: coffee.rating,
        afterOverdraw: afterOverdraw,
        reason: reason,
        brewRatings: ratings,
      ),
    );
    if (decision == null || !mounted) return false;
    final s = AppLocalizations.of(context)!;
    try {
      await repository.setCoffeeArchived(
        coffee.id,
        archived: true,
        rating: decision.rating,
      );
      if (!mounted) return true;
      message(s.beanArchived);
      return true;
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
      return false;
    }
  }

  Future<void> addTool() async {
    final saved = await showToolForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context)!.toolSaved);
    }
  }

  /// The floating button's label and action on the tab shown.
  (String, VoidCallback) _floatingAction(AppLocalizations s) => switch (tab) {
    3 => switch (equipmentSection) {
      EquipmentSection.recipients => (
        s.addRecipient,
        () async {
          await showRecipientForm(context, repository);
        },
      ),
      EquipmentSection.methods => (s.addMethod, addMethod),
      EquipmentSection.grinders => (s.addGrinder, addGrinder),
      EquipmentSection.water => (s.addWaterProfile, addWaterProfile),
      EquipmentSection.tools => (s.addTool, addTool),
    },
    // Home offers a bean instead of a brew when none is left to brew with.
    1 => (s.newBean, addCoffee),
    0 when journal.everyCoffeeArchived => (s.newBean, addCoffee),
    _ => (
      s.actionBrew,
      () => openBrewForm(journal.coffees, seed: journal.latestUsableBrew),
    ),
  };

  @override
  void showRoasters({String? roaster}) =>
      openRoasters(context, journal, this, roaster: roaster);

  Widget _tabs(JournalData data) => LazyIndexedStack(
    index: tab,
    children: [
      HomeTab(data: data, actions: this),
      BeansTab(
        data: data,
        actions: this,
        tabs: beanTabs,
        onOpenCalendar: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ListenableBuilder(
              listenable: journal,
              builder: (context, _) => FreshnessCalendarPage(
                lots: calendarLots(journal.data, journal.portions),
                onCoffee: showCoffeeDetailsById,
              ),
            ),
          ),
        ),
        options: journal.listOptions,
        onOptionsChanged: journal.changeListOptions,
      ),
      HistoryTab(
        data: data,
        actions: this,
        filters: historyFilters,
        options: journal.listOptions,
        onOptionsChanged: journal.changeListOptions,
      ),
      EquipmentPage(
        repository: repository,
        section: equipmentSection,
        onSectionChanged: (section) =>
            setState(() => equipmentSection = section),
        showArchived: showArchivedEquipment,
        onShowMethodBrews: (method) {
          // Every brew of the method, archived ones too, as its card
          // counts them.
          historyFilters.update(() {
            historyFilters.resetForNavigation();
            historyFilters.methodId = method.id;
            historyFilters.methodName = method.name;
            historyFilters.showArchived = true;
          });
          setState(() => tab = 2);
        },
        onBrewWithMethod: (method) =>
            openBrewForm(journal.coffees, initialMethodId: method.id),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: journal,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final (fabLabel, fabAction) = _floatingAction(s);
      // Back from another tab returns to Home instead of leaving the app.
      return PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => tab = 0);
        },
        child: Scaffold(
          // Under a sheet, the keyboard is the sheet's business: resizing here
          // would lay out every tab on each frame of its animation.
          resizeToAvoidBottomInset: ModalRoute.of(context)?.isCurrent ?? true,
          appBar: JournalAppBar(
            onCafes: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CafesPage(
                  repository: repository.cafes,
                  photos: widget.photos,
                ),
              ),
            ),
            tab: tab,
            showArchivedEquipment: showArchivedEquipment,
            onStats: () {
              final data = journal.data;
              openStats(data.coffees, data.brews, data.lots, data.components);
            },
            onRoasters: showRoasters,
            onToggleArchivedEquipment: () =>
                setState(() => showArchivedEquipment = !showArchivedEquipment),
            onSettings: openSettings,
          ),
          body: journal.hasError
              ? Center(child: Text(s.dataError))
              : journal.loading
              ? const Center(child: CircularProgressIndicator())
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) => floatingExtension.onScroll(
                    notification,
                    expandWhenIdle:
                        tab == 1 || (tab == 0 && journal.everyCoffeeArchived),
                  ),
                  child: _tabs(journal.data),
                ),
          floatingActionButton: HiddenWithKeyboard(
            child: ValueListenableBuilder<bool>(
              valueListenable: floatingExtension,
              // Import dialogs outlive this subtree when the keyboard opens.
              builder: (_, extended, _) =>
                  tab == 1 || (tab == 0 && journal.everyCoffeeArchived)
                  ? BeanAddButton(
                      extended: extended,
                      onManual: addCoffee,
                      actions: beanImportActions(
                        context,
                        this,
                        journal.coffees,
                        widget.incoming,
                        searchLoffee: widget.loffee == null
                            ? null
                            : () => importLoffeeBean(
                                context,
                                this,
                                journal.coffees,
                                widget.loffee!,
                              ),
                      ),
                    )
                  : SmoothFloatingButton(
                      isExtended: extended,
                      tooltip: extended ? null : fabLabel,
                      onPressed: fabAction,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(fabLabel),
                    ),
            ),
          ),
          bottomNavigationBar: JournalNavigationBar(
            selected: tab,
            onSelected: (index) => setState(() => tab = index),
          ),
        ),
      );
    },
  );
}
