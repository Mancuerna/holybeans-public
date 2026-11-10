import 'dart:convert';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_add_button.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Brings the coffees in [text] (a card file, a QR code's text or an AI's
/// answer) into the journal. One coffee opens the coffee form filled in,
/// after asking when it is already there; several open a list to review.
Future<void> importBeansFromText(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
  String text,
) async {
  final s = AppLocalizations.of(context)!;
  final List<ReadBean> read;
  try {
    read = await _readInBackground(text);
  } on BeanReadException catch (exception, stack) {
    // Says where reading stopped, in the device log only.
    reportError(exception, stack);
    if (context.mounted) actions.message(_readErrorMessage(s, exception.error));
    return;
  }
  if (!context.mounted) return;
  await _reviewBeans(context, actions, coffees, read);
}

Future<List<ReadBean>> _readInBackground(String text) =>
    Isolate.run(() => readBeans(text));

String _readErrorMessage(AppLocalizations s, BeanReadError error) =>
    switch (error) {
      BeanReadError.notJson => s.importInvalidJson,
      BeanReadError.noBeans => s.importNothing,
      BeanReadError.newerVersion => s.importNewer,
      BeanReadError.tooLarge => s.importCardTooLarge,
    };

String _fieldName(AppLocalizations s, String field) => switch (field) {
  'roaster' => s.roaster,
  'roastDate' => s.roastDate,
  'roastLevel' => s.roastLevel,
  'price' => s.paidPrice,
  'bagGrams' => s.purchasedQuantity,
  'shopUrl' => s.shopUrl,
  'altitudeMeters' => s.altitude,
  'altitudeMaxMeters' => s.altitudeMax,
  _ => field,
};

Future<void> _reviewBeans(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
  List<ReadBean> read,
) async {
  if (!context.mounted) return;
  final s = AppLocalizations.of(context)!;
  if (read.length > 1) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BeanImportPage(beans: read, coffees: coffees, actions: actions),
      ),
    );
    return;
  }
  final single = read.single;
  if (single.dropped.isNotEmpty) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('import-dropped'),
        title: Text(s.importDroppedTitle),
        content: SingleChildScrollView(
          child: Text(
            s.importDroppedBody(
              single.dropped
                  .toSet()
                  .map((field) => _fieldName(s, field))
                  .join(', '),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('import-dropped-review'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.importReviewAction),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
  }
  final card = single.bean;
  if (await confirmBeanImport(context, actions, coffees, card)) {
    await actions.addCoffeeFromCard(card);
  }
}

Future<bool> confirmBeanImport(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
  SharedBean card,
) async {
  final s = AppLocalizations.of(context)!;
  if (existingCoffee(card, coffees) case final mine?) {
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('import-duplicate'),
        title: Text(s.importAlreadyHave(card.name)),
        content: Text(s.importAlreadyHaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.importOpenMine),
          ),
          FilledButton(
            key: const ValueKey('import-add-anyway'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.importAddAnyway),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    if (!choice) {
      actions.showCoffeeDetailsById(mine.id);
      return false;
    }
  }
  return true;
}

/// A coffee card read from a QR code; null when cancelled, or when the
/// scanner could not start, which [actions] tells the user.
Future<String?> scanBeanQr(
  JournalActions actions,
  AppLocalizations s,
  IncomingShares incoming,
) async {
  try {
    return await incoming.scanQr();
  } on QrScanFailed catch (error, stack) {
    reportError(error, stack);
    actions.message(s.scanFailed);
    return null;
  }
}

/// Shared entry points used by the bean button, including the existing readers.
List<BeanAddAction> beanImportActions(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
  IncomingShares? incoming, {
  VoidCallback? searchLoffee,
}) {
  final s = AppLocalizations.of(context)!;
  Future<void> importText(String? text) async {
    if (text == null || !context.mounted) return;
    await importBeansFromText(context, actions, coffees, text);
  }

  Future<void> run(Future<void> Function() work) async {
    try {
      await work();
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.importFailed);
    }
  }

  return [
    if (searchLoffee != null)
      BeanAddAction(
        id: 'import-loffee',
        icon: Icons.travel_explore_outlined,
        label: s.loffeeSearchTitle,
        run: searchLoffee,
      ),
    if (incoming != null)
      BeanAddAction(
        id: 'import-scan',
        icon: Icons.qr_code_scanner_rounded,
        label: s.importScanQr,
        run: () =>
            run(() async => importText(await scanBeanQr(actions, s, incoming))),
      ),
    BeanAddAction(
      id: 'import-paste',
      icon: Icons.content_paste_rounded,
      label: s.importPaste,
      run: () => run(() async {
        final read = await _pasteCard(context);
        if (read != null && context.mounted) {
          await _reviewBeans(context, actions, coffees, read);
        }
      }),
    ),
    BeanAddAction(
      id: 'import-file',
      icon: Icons.file_open_outlined,
      label: s.importOpenFile,
      run: () => run(() async {
        final file = await openFile();
        if (file != null) {
          await importText(utf8.decode(await file.readAsBytes()));
        }
      }),
    ),
    BeanAddAction(
      id: 'import-ai',
      icon: Icons.smart_toy_outlined,
      label: s.importCopyAi,
      run: () => run(() async {
        await Clipboard.setData(
          ClipboardData(text: s.beanAiInstructions(aiCardExample)),
        );
        actions.message(s.aiInstructionsCopied);
      }),
    ),
  ];
}

/// The card shape shown to an AI, with placeholder values rather than a
/// real coffee it might copy.
final aiCardExample = const JsonEncoder.withIndent('  ').convert({
  'format': beanFormat,
  'version': beanFormatVersion,
  'beans': [
    {
      'name': 'Coffee name',
      'roaster': 'Roaster',
      'origins': [
        {
          'country': 'Country',
          'region': 'Region',
          'farm': 'Farm',
          'producer': 'Producer',
          'variety': 'Variety',
          'process': 'Process',
          'altitudeMeters': 1800,
          'altitudeMaxMeters': 2000,
          'harvest': '2025',
        },
      ],
      'roastLevel': 'light',
      'decaf': false,
      'flavorNotes': ['note', 'note'],
      'price': 18.5,
      'bagGrams': 250,
      'roastDate': '2026-09-30',
      'shopUrl': 'https://shop.example/coffee',
    },
  ],
});

/// Several coffees read at once, to choose which to add. Coffees already in
/// the journal start unticked; fields that could not be read are named.
class BeanImportPage extends StatefulWidget {
  const BeanImportPage({
    super.key,
    required this.beans,
    required this.coffees,
    required this.actions,
  });

  final List<ReadBean> beans;
  final List<Coffee> coffees;
  final JournalActions actions;

  @override
  State<BeanImportPage> createState() => _BeanImportPageState();
}

class _BeanImportPageState extends State<BeanImportPage> {
  late final _chosen = [
    for (final read in widget.beans)
      existingCoffee(read.bean, widget.coffees) == null,
  ];
  bool _saving = false;

  Future<void> _import() async {
    final s = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    var added = 0;
    try {
      for (final (index, read) in widget.beans.indexed) {
        if (!_chosen[index]) continue;
        await widget.actions.repository.createCoffeeFromCard(read.bean);
        added++;
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.importFailed);
    }
    if (!mounted) return;
    if (added > 0) widget.actions.message(s.importDone(added));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final count = _chosen.where((chosen) => chosen).length;
    return Scaffold(
      appBar: AppBar(title: Text(s.importReviewTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
        itemCount: widget.beans.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final read = widget.beans[index];
          final bean = read.bean;
          final origin = bean.origins
              .map(
                (origin) => [
                  origin.country,
                  origin.region,
                ].whereType<String>().join(', '),
              )
              .where((text) => text.isNotEmpty)
              .join(' / ');
          final bag = [
            if (bean.bagGrams case final grams?)
              formatGrams(grams, regionalLocale.toString()),
            if (bean.priceCents case final cents?)
              euroNumberFormat(regionalLocale.toString()).format(cents / 100),
          ].join(', ');
          return CheckboxListTile(
            key: ValueKey('import-bean-$index'),
            value: _chosen[index],
            onChanged: _saving
                ? null
                : (value) => setState(() => _chosen[index] = value ?? false),
            title: Text(bean.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bean.roaster.isEmpty ? s.importNoRoaster : bean.roaster,
                  style: muted,
                ),
                if (origin.isNotEmpty) Text(origin, style: muted),
                if (bag.isNotEmpty) Text(bag, style: muted),
                if (existingCoffee(bean, widget.coffees) != null)
                  Text(
                    s.importDuplicate,
                    style: muted?.copyWith(color: theme.colorScheme.primary),
                  ),
                if (read.dropped.isNotEmpty)
                  Text(
                    s.importDropped(
                      read.dropped
                          .map((field) => _fieldName(s, field))
                          .join(', '),
                    ),
                    style: muted,
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('import-beans-confirm'),
        onPressed: count == 0 || _saving ? null : _import,
        icon: const Icon(Icons.download_done_rounded),
        label: Text(s.importSelected(count)),
      ),
    );
  }
}

/// Asks for the card's text in a box, filled in from the clipboard when the
/// system lets the app read it; otherwise the person pastes it there, which
/// Android always allows. Returns the parsed cards, or null when cancelled.
Future<List<ReadBean>?> _pasteCard(BuildContext context) async {
  String? clipboard;
  try {
    clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException catch (error, stack) {
    reportError(error, stack);
  }
  if (!context.mounted) return null;
  return showDialog<List<ReadBean>>(
    context: context,
    builder: (_) => _PasteDialog(initial: clipboard ?? ''),
  );
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog({required this.initial});

  final String initial;

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  late final _text = TextEditingController(text: widget.initial);
  BeanReadError? _error;
  bool _submitted = false;

  Future<void> _submit() async {
    if (_submitted) return;
    setState(() => _submitted = true);
    try {
      final read = await _readInBackground(_text.text);
      if (!mounted) return;
      Navigator.pop(context, read);
    } on BeanReadException catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() {
          _error = error.error;
          _submitted = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      key: const ValueKey('paste-dialog'),
      title: Text(s.importPaste),
      content: SingleChildScrollView(
        child: TextField(
          key: const ValueKey('paste-text'),
          controller: _text,
          autofocus: widget.initial.isEmpty,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: s.importPasteHint,
            errorText: _error == null ? null : _readErrorMessage(s, _error!),
            errorMaxLines: 8,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => FilledButton(
            key: const ValueKey('paste-import'),
            onPressed: _submitted || _text.text.trim().isEmpty ? null : _submit,
            child: Text(s.importAction),
          ),
        ),
      ],
    );
  }
}
