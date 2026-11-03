import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/cupping/cupping_identification.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';
import 'package:holybeans/ui/cupping/cupping_setup.dart';
import 'package:holybeans/ui/cupping/cupping_share_sheet.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

Future<void> openCupping(
  BuildContext context,
  JournalRepository repository, {
  CuppingSession? session,
}) async {
  final s = AppLocalizations.of(context)!;
  try {
    session ??= await repository.cuppingSession(
      await repository.createCuppingSession(CuppingDraft()),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CuppingPage(repository: repository, session: session!),
      ),
    );
  } catch (e, stack) {
    reportError(e, stack);
    if (context.mounted) {
      showOperationError(context, e, s.saveFailed);
    }
  }
}

class CuppingPage extends StatefulWidget {
  const CuppingPage({
    super.key,
    required this.repository,
    required this.session,
  });
  final JournalRepository repository;
  final CuppingSession session;
  @override
  State<CuppingPage> createState() => _CuppingPageState();
}

class _CuppingPageState extends State<CuppingPage> with WidgetsBindingObserver {
  late final model = CuppingModel(
    widget.repository,
    widget.session,
    CuppingDraft.fromJson(widget.session.draftJson),
  );
  final formKey = GlobalKey<FormState>();
  bool loaded = false;
  bool closing = false;
  bool allowPop = false;
  Object? loadError;
  bool sharing = false;

  Future<void> _share() async {
    setState(() => sharing = true);
    await shareCuppingFlow(context, widget.repository, model.session.id);
    if (mounted) setState(() => sharing = false);
  }

  Future<void> _confirmReveal() async {
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cuppingIdentify),
        content: Text(s.cuppingRevealHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('cupping-confirm-reveal'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.cuppingIdentify),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      await model.reveal();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      await model.loadCatalogs();
      if (mounted) setState(() => loaded = true);
    } catch (e, stack) {
      reportError(e, stack);
      if (mounted) setState(() => loadError = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      model.flush();
    }
    if (state == AppLifecycleState.resumed) model.tick();
  }

  Future<void> _close() async {
    if (closing || model.busy) return;
    closing = true;
    if (await model.flush() && mounted) {
      setState(() => allowPop = true);
      Navigator.of(context).pop();
    }
    closing = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final identifying =
              model.draft.blind &&
              model.draft.revealed &&
              !model.completed &&
              !model.reviewingBlindScores;
          final scores =
              model.completed ||
              model.draft.phase == CuppingPhase.tasting ||
              model.draft.phase == CuppingPhase.review;
          return Scaffold(
            appBar: AppBar(
              title: Text(
                model.completed
                    ? s.cuppingSaved
                    : model.draft.blind
                    ? s.cuppingBlind
                    : s.cuppingTitle,
              ),
              leading: BackButton(onPressed: _close),
              actions: [
                if (model.completed && loaded)
                  IconButton(
                    key: const ValueKey('cupping-share'),
                    tooltip: s.cuppingShare,
                    onPressed: sharing ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                  ),
                const _CuppingGuideButton(),
              ],
            ),
            body: loadError != null
                ? Center(child: Text(s.dataError))
                : !loaded
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (model.error != null)
                        _CuppingErrorBanner(model: model),
                      Expanded(
                        child: identifying
                            ? CuppingIdentification(model: model)
                            : scores
                            ? CuppingScores(model: model)
                            : model.draft.phase == CuppingPhase.setup
                            ? CuppingSetup(model: model, formKey: formKey)
                            : CuppingClock(model: model),
                      ),
                    ],
                  ),
            bottomNavigationBar: !loaded || model.completed
                ? null
                : _CuppingActions(
                    model: model,
                    formKey: formKey,
                    scores: scores,
                    onReveal: _confirmReveal,
                  ),
          );
        },
      ),
    );
  }
}

class CuppingClock extends StatelessWidget {
  const CuppingClock({super.key, required this.model});
  final CuppingModel model;

  Future<void> _editTarget(BuildContext context, bool infusion) async {
    final s = AppLocalizations.of(context)!;
    var input = formatCuppingDuration(
      infusion ? model.draft.crustSeconds : model.draft.tastingSeconds,
    );
    final formKey = GlobalKey<FormState>();
    final seconds = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cuppingEditTime),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const ValueKey('cupping-target-input'),
            initialValue: input,
            onChanged: (text) => input = text,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: infusion ? s.cuppingCrustTime : s.cuppingTasteTime,
            ),
            validator: (text) {
              final value = parseCuppingDuration(text ?? '');
              final valid =
                  value != null &&
                  (infusion
                      ? value >= 60 &&
                            value <= 600 &&
                            value < model.draft.tastingSeconds
                      : value > model.draft.crustSeconds && value <= 3600);
              return valid ? null : s.cuppingTimeError;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('cupping-save-target'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(parseCuppingDuration(input));
              }
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (seconds != null) model.setTarget(infusion: infusion, seconds: seconds);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final infusion = model.draft.phase == CuppingPhase.infusion;
    final target = infusion
        ? model.draft.crustSeconds
        : model.draft.tastingSeconds;
    final left = (target - model.elapsed).clamp(0, target);
    String time(int seconds) => formatCuppingDuration(seconds);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          infusion
              ? (left == 0 ? s.cuppingCrustDue : s.cuppingInfusion)
              : (left == 0 ? s.cuppingTasteDue : s.cuppingCooling),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            time(left),
            key: const ValueKey('cupping-countdown'),
            style: Theme.of(context).textTheme.displayLarge,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text('${s.time}: ${time(model.elapsed)}')),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value:
              ((model.elapsed - (infusion ? 0 : model.draft.crustSeconds)) /
                      (infusion ? target : target - model.draft.crustSeconds))
                  .clamp(0, 1),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('cupping-pause'),
              onPressed: model.busy ? null : model.toggleClock,
              icon: Icon(model.clockPaused ? Icons.play_arrow : Icons.pause),
              label: Text(model.clockPaused ? s.cuppingResume : s.cuppingPause),
            ),
            OutlinedButton.icon(
              key: const ValueKey('cupping-reset-clock'),
              onPressed: model.busy ? null : model.resetClock,
              icon: const Icon(Icons.restart_alt),
              label: Text(s.cuppingResetClock),
            ),
            TextButton.icon(
              key: const ValueKey('cupping-edit-target'),
              onPressed: model.busy
                  ? null
                  : () => _editTarget(context, infusion),
              icon: const Icon(Icons.edit_outlined),
              label: Text('${s.cuppingEditTime}: ${time(target)}'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(infusion ? s.cuppingCrustHint : s.cuppingTasteHint),
        const SizedBox(height: 24),
        FilledButton(
          key: ValueKey(infusion ? 'cupping-break' : 'cupping-taste'),
          onPressed: model.busy || (infusion && model.elapsed < 60)
              ? null
              : (infusion ? model.breakCrust : model.taste),
          child: Text(infusion ? s.cuppingBroken : s.cuppingTaste),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < model.draft.cups.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(
              model.draft.blind ? String.fromCharCode(65 + i) : '${i + 1}',
            ),
            title: Text(cuppingCoffee(model, i, s)),
          ),
      ],
    );
  }
}

/// The cupping protocol, from the app bar.
class _CuppingGuideButton extends StatelessWidget {
  const _CuppingGuideButton();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: s.cuppingGuide,
      icon: const Icon(Icons.help_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.cuppingGuide),
          content: SingleChildScrollView(child: Text(s.cuppingGuideText)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// What failed to save, with a retry.
class _CuppingErrorBanner extends StatelessWidget {
  const _CuppingErrorBanner({required this.model});

  final CuppingModel model;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                model.error is CuppingStockException
                    ? s.cuppingStockError
                    : journalWriteErrorText(context, model.error, s.saveFailed),
              ),
            ),
            IconButton(
              tooltip: s.save,
              onPressed: model.busy ? null : model.flush,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

/// The step the session moves on with: pour after setup; identify, review
/// or finish once tasting.
class _CuppingActions extends StatelessWidget {
  const _CuppingActions({
    required this.model,
    required this.formKey,
    required this.scores,
    required this.onReveal,
  });

  final CuppingModel model;
  final GlobalKey<FormState> formKey;

  /// Whether the scores are showing.
  final bool scores;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: scores
            ? model.draft.blind && !model.draft.revealed
                  ? FilledButton(
                      key: const ValueKey('cupping-identify'),
                      onPressed: model.draft.canReveal && !model.busy
                          ? onReveal
                          : null,
                      child: Text(s.cuppingIdentify),
                    )
                  : _finishButtons(s)
            : model.draft.phase != CuppingPhase.setup
            ? null
            : FilledButton(
                key: const ValueKey('cupping-pour'),
                onPressed: model.busy ? null : () => _pour(context, s),
                child: Text(s.cuppingPour),
              ),
      ),
    );
  }

  Widget _finishButtons(AppLocalizations s) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (model.draft.blind)
        TextButton(
          key: const ValueKey('cupping-review-scores'),
          onPressed: model.busy
              ? null
              : () => model.reviewBlindScores(!model.reviewingBlindScores),
          child: Text(
            model.reviewingBlindScores
                ? s.cuppingIdentify
                : s.cuppingReviewScores,
          ),
        ),
      FilledButton(
        key: const ValueKey('cupping-finish'),
        onPressed: !model.canFinish || model.busy
            ? null
            : () async {
                FocusManager.instance.primaryFocus?.unfocus();
                await model.finish();
              },
        child: model.busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              )
            : Text(s.cuppingFinish),
      ),
    ],
  );

  void _pour(BuildContext context, AppLocalizations s) {
    if (!(formKey.currentState?.validate() ?? false) || !model.canStart) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.cuppingSetupError)));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    model.start();
  }
}
