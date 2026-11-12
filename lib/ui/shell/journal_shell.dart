import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/freshness_calendar_data.dart';
import 'package:holybeans/data/repositories/journal_mutations.dart';
import 'package:holybeans/data/repositories/journal_queries.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock_adjustment_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
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
import 'package:holybeans/ui/core/app_services.dart';
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
import 'package:holybeans/ui/profiles/profile_library_page.dart';
import 'package:holybeans/ui/roasters/roaster_routes.dart';
import 'package:holybeans/ui/settings/beanconqueror_import_page.dart';
import 'package:holybeans/ui/settings/pours_from_curves.dart';
import 'package:holybeans/ui/settings/settings_page.dart';
import 'package:holybeans/ui/shell/floating_button_state.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_app_bar.dart';
import 'package:holybeans/ui/shell/journal_navigation_bar.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';
import 'package:holybeans/ui/shell/retained_journal_tab.dart';
import 'package:holybeans/ui/shell/system_surfaces.dart';
import 'package:holybeans/ui/stats/live_stats_page.dart';

/// The app's main screen: navigation between Home, Beans, History and
/// Equipment, the floating action, and the [JournalActions] the tabs use.
class JournalShell extends StatefulWidget {
  const JournalShell({
    super.key,
    this.locale,
    required this.onLocaleChanged,
    this.driveTile,
  });

  final Widget? driveTile;

  /// The explicitly chosen app locale, or null when following the system.
  final Locale? locale;
  final ValueChanged<Locale?> onLocaleChanged;

  @override
  State<JournalShell> createState() => _JournalShellState();
}

class _JournalShellState extends State<JournalShell>
    with SingleTickerProviderStateMixin
    implements JournalRead, JournalNavigation, JournalCommands {
  late final services = AppServicesScope.read(context);
  late final actions = JournalActions(
    read: this,
    navigation: this,
    commands: this,
  );
  @override
  late final queries = JournalQueries(repository);
  @override
  late final mutations = JournalMutations(repository);
  @override
  FreezerRepository get freezer => repository.freezer;
  @override
  StockAdjustmentRepository get stockEdits => repository.stockEdits;
  JournalRepository get repository => services.repository;

  @override
  PhotoStore? get photos => services.photos;

  @override
  late final BackupCenter backupCenter = BackupCenter(
    database: services.database,
    photos: services.photos,
    services: services.backupServices,
  );
  late final BackupActions backups = BackupActions(
    center: backupCenter,
    repository: repository,
    photos: services.photos,
    message: message,
  );
  BrewParameterSettings get parameterSettings => services.parameterSettings;
  RateReminderSettings get reminderSettings => services.reminderSettings;

  /// The live journal and the settings the tabs follow.
  late final JournalViewModel journal = JournalViewModel(
    repository: repository,
    parameterSettings: parameterSettings,
    listOptionsSettings: ListOptionsSettings(services.database),
  );
  @override
  ShareTemplateSettings get templateSettings => services.templateSettings;
  late final brewActions = BrewActions(
    context: context,
    services: services,
    methods: () => methods,
    message: message,
    showBeans: () => setState(() => tab = 1),
    confirmArchive: (coffee, afterOverdraw, reason) => confirmCoffeeArchive(
      coffee,
      afterOverdraw: afterOverdraw,
      reason: reason,
    ),
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
    services.openRate?.addListener(_openRateFromReminder);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openRateFromReminder(),
    );
    backupCenter.start();
    surfaces.start();
    if (services.incoming case final incoming?) {
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
        actions: actions,
        journal: journal,
        incoming: services.incoming,
      );
    } else if (isShareTemplateFile(text)) {
      final settings = templateSettings;
      final imported = await importShareTemplate(
        context,
        settings,
        source: text,
      );
      if (imported != null && mounted) {
        message(AppLocalizations.of(context).shareTemplateSaved);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ShareTemplatesPage(settings: settings, style: imported.style),
          ),
        );
      }
    } else {
      await importBeansFromText(context, actions, journal.coffees, text);
    }
  }

  @override
  Future<void> addCoffeeFromCard(
    SharedBean card, {
    String? initialNotes,
    String? roastLevelHint,
    Future<Uint8List> Function()? importPhoto,
  }) async {
    final saved = await showFormSheet<Object>(
      context,
      CoffeeForm(
        repository: repository,
        photos: services.photos,
        card: card,
        initialNotes: initialNotes,
        roastLevelHint: roastLevelHint,
        importPhoto: importPhoto,
      ),
    );
    if (saved != null && mounted) {
      message(AppLocalizations.of(context).beanSaved);
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
    surfaces.relabel(surfaceLabels(AppLocalizations.of(context)));
  }

  @override
  void dispose() {
    historyFilters.dispose();
    unawaited(_arrivals?.cancel());
    journal.dispose();
    backupCenter.dispose();
    services.openRate?.removeListener(_openRateFromReminder);
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
        photos: services.photos,
        savedPhotos: savedPhotos,
      ),
    );
    if (saved is String && mounted) {
      message(AppLocalizations.of(context).frozenSaved(saved));
    } else if (saved == true && mounted) {
      message(AppLocalizations.of(context).beanSaved);
    }
  }

  Future<void> addMethod() async {
    final saved = await showMethodForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context).methodSaved);
    }
  }

  Future<void> addGrinder() async {
    final saved = await showGrinderForm(context, repository);
    if (saved != null && mounted) {
      message(AppLocalizations.of(context).grinderSaved);
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
      message(AppLocalizations.of(context).waterProfileSaved);
    }
  }

  Future<void> _importBeanconqueror() async {
    final summary = await importFromBeanconqueror(
      context,
      repository: repository,
      photos: services.photos,
      folder: services.exportFolder,
    );
    if (summary == null || !mounted) return;
    message(bqSummaryMessage(AppLocalizations.of(context), summary));
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
          onConfigureLoffee: services.loffee == null
              ? null
              : () => configureLoffeeKey(context, services.loffee!.keys),
          onFillPoursFromCurves: () => fillPoursFromCurves(
            context,
            repository: repository,
            message: message,
          ),
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
        actions: actions.read,
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
    final brewId = services.openRate?.value;
    if (brewId == null || !mounted) return;
    services.openRate!.value = null;
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
      showCoffeeDetailsSheet(context, actions, coffee, data);

  @override
  void showBrewDetails(Brew brew, Coffee? coffee, JournalData data) =>
      showBrewDetailsSheet(context, actions, brew, coffee, data);

  @override
  Future<void> compareBrew(Brew brew, JournalData data) =>
      showBrewComparison(context, actions, brew, data);

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
    final s = AppLocalizations.of(context);
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
      message(AppLocalizations.of(context).toolSaved);
    }
  }

  /// The floating button's label and action on the tab shown.
  (String, VoidCallback) _floatingAction(AppLocalizations s) => switch (tab) {
    3 => switch (equipmentSection) {
      EquipmentSection.portafilters => (
        s.addPortafilter,
        () async {
          await showRecipientForm(context, repository, null, true);
        },
      ),
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
      openRoasters(context, journal, actions.navigation, roaster: roaster);

  Widget _tabs(JournalData data) {
    final children = [
      HomeTab(data: data, actions: actions),
      BeansTab(
        data: data,
        actions: actions,
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
        actions: actions,
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
    ];
    return LazyIndexedStack(
      index: tab,
      children: children.indexed
          .map(
            (entry) => RetainedJournalTab(
              revision: (
                data,
                methods,
                portions,
                hiddenParameters,
                journal.listOptions,
                equipmentSection,
                showArchivedEquipment,
              ),
              selected: tab == entry.$1,
              child: entry.$2,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: journal,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
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
            onProfiles: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ProfileLibraryPage(
                  repository: repository.extractionProfiles,
                ),
              ),
            ),
            onCafes: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CafesPage(
                  repository: repository.cafes,
                  photos: services.photos,
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
                        actions,
                        journal.coffees,
                        services.incoming,
                        searchLoffee: services.loffee == null
                            ? null
                            : () => importLoffeeBean(
                                context,
                                actions,
                                journal.coffees,
                                services.loffee!,
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
