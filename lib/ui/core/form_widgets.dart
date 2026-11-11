import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/data/database/journal_write_gate.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';
import 'package:intl/intl.dart';

export 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Shows [form] in a modal bottom sheet. The sheet rebuilds its content
/// on every frame of the keyboard animation; since [form] is created once
/// and handed back each time, Flutter skips rebuilding the whole form.
Future<T?> showFormSheet<T>(
  BuildContext context,
  Widget form, {
  bool useSafeArea = false,
}) {
  final navigator = Navigator.of(context);
  final strings = MaterialLocalizations.of(context);
  return navigator.push<T>(
    FormSheetRoute<T>(
      builder: (_) => form,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: strings.scrimLabel,
      barrierOnTapHint: strings.scrimOnTapHint(strings.bottomSheetLabel),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      useSafeArea: useSafeArea,
    ),
  );
}

/// Frame of a form bottom sheet: title, scrolling fields and fixed
/// Cancel/Save buttons.
class SheetFrame extends StatefulWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.saving,
    required this.onSave,
    this.showScrollCue = false,
    this.writesJournal = true,
    this.header,
  });

  final String title;

  /// Shown under the title and outside the scrolling fields, e.g. the
  /// recipe figures of a brew while it is written.
  final Widget? header;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;
  final bool showScrollCue;
  final bool writesJournal;

  @override
  State<SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<SheetFrame> {
  bool _waiting = false;

  Future<void> _save() async {
    final model = widget.writesJournal ? DriveSyncScope.maybeOf(context) : null;
    if (_waiting || widget.saving) return;
    if (model?.applying == true) {
      setState(() => _waiting = true);
      try {
        await waitForDriveCheck(model!);
      } on TimeoutException {
        if (mounted && ModalRoute.of(context)?.isCurrent != false) {
          showOperationError(
            context,
            const JournalReadOnlyException(),
            AppLocalizations.of(context)!.saveFailed,
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _waiting = false);
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    }
    if (model != null && !model.backup.database.writeGate.writable) {
      showOperationError(
        context,
        const JournalReadOnlyException(),
        AppLocalizations.of(context)!.saveFailed,
      );
      return;
    }
    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final screen = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final available =
        screen - keyboard - MediaQuery.paddingOf(context).top - 20;
    final height = math.min(available * 0.98, screen * 0.88);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              ?widget.header,
              Expanded(
                child: Form(
                  key: widget.formKey,
                  child: SheetScrollArea(
                    showScrollCue: widget.showScrollCue,
                    children: widget.children,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => FormExitGuard.cancel(context),
                        child: Text(s.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.saving || _waiting ? null : _save,
                        child: Text(_waiting ? s.driveSyncChecking : s.save),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrolling fields of a form sheet, with a cue while more lies below.
class SheetScrollArea extends StatefulWidget {
  const SheetScrollArea({
    super.key,
    required this.children,
    required this.showScrollCue,
  });

  final List<Widget> children;
  final bool showScrollCue;

  @override
  State<SheetScrollArea> createState() => _SheetScrollAreaState();
}

class _SheetScrollAreaState extends State<SheetScrollArea> {
  bool _showCue = true;

  void _updateCue(ScrollMetrics metrics) {
    final shouldShow = widget.showScrollCue && metrics.extentAfter > 1;
    if (_showCue == shouldShow) return;
    // A scroll can start during layout, when the content shrinks under a
    // list scrolled to its end: the cue then changes on the next frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showCue != shouldShow) {
          setState(() => _showCue = shouldShow);
        }
      });
      return;
    }
    setState(() => _showCue = shouldShow);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _updateCue(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _updateCue(notification.metrics);
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              itemCount: widget.children.length,
              itemBuilder: (context, index) => widget.children[index],
              separatorBuilder: (context, index) => const SizedBox(height: 20),
            ),
            if (widget.showScrollCue && _showCue)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 44,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.surface.withValues(alpha: 0),
                          colors.surface.withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              key: const ValueKey('brew-sheet-scroll-cue'),
                              color: colors.onSecondaryContainer,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int? parsePriceCents(String text) {
  final clean = plainNumberText(text);
  if (clean.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:[,.](\d{1,2}))?$').firstMatch(clean);
  if (match == null) return null;
  final euros = int.tryParse(match.group(1)!);
  final cents = int.tryParse((match.group(2) ?? '').padRight(2, '0')) ?? 0;
  if (euros == null || euros > (0x7fffffffffffffff - cents) ~/ 100) {
    return null;
  }
  return euros * 100 + cents;
}

Widget numberField(
  BuildContext context,
  TextEditingController controller,
  String label, {
  String? helperText,
  bool integer = false,
  bool positive = true,
  double? max,
  Key? key,
  Widget? suffix,
  String? Function(double?)? validate,
}) {
  final s = AppLocalizations.of(context)!;
  return TextFormField(
    key: key,
    controller: controller,
    inputFormatters: [decimalInputFormatter],
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      // Half-width fields wrap a longer note instead of cutting it.
      helperMaxLines: 3,
      errorMaxLines: 4,
      suffixIcon: suffix,
    ),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return validate?.call(null);
      final parsed = parseNumber(value);
      if (parsed == null ||
          !parsed.isFinite ||
          (positive && parsed <= 0) ||
          (!positive && parsed < 0) ||
          (max != null && parsed > max) ||
          (integer && parsed != parsed.roundToDouble())) {
        return s.invalidNumber;
      }
      return validate?.call(parsed);
    },
  );
}

/// The device region, also used by numeric labels outside forms.
String get fieldLocale => regionalLocale.toString();

_FieldFormats? _cachedFieldFormats;

_FieldFormats get _fieldFormats {
  final locale = fieldLocale;
  final cached = _cachedFieldFormats;
  if (cached != null && cached.locale == locale) return cached;
  return _cachedFieldFormats = _FieldFormats(locale);
}

// NumberFormat is mutable: keep instances private and only retain formats for
// the current device region, rebuilding them when that region changes.
class _FieldFormats {
  _FieldFormats(this.locale) : decimal = NumberFormat.decimalPattern(locale);

  final String locale;
  final NumberFormat decimal;
  final _numbers = <int, NumberFormat>{};

  String number(double value, int decimals) => _numbers
      .putIfAbsent(decimals, () => NumberFormat('0.${'#' * decimals}', locale))
      .format(value);
}

final decimalInputFormatter = TextInputFormatter.withFunction((old, next) {
  if (!next.composing.isCollapsed) return next;
  final separator = _fieldFormats.decimal.symbols.DECIMAL_SEP;
  return next.copyWith(text: next.text.replaceAll(RegExp(r'[.,]'), separator));
});

/// [value] the way a field shows it: the device's decimal separator, no
/// grouping and at most [decimals] decimals ("17,1" in Spanish, "15" rather
/// than "15.0"). [parseNumber] reads it back.
String fieldNumber(double value, {int decimals = 3}) =>
    _fieldFormats.number(value, decimals);

/// A saved [value] as a field shows it, without rounding (an edit must not
/// change a number nobody touched): "15" for 15.0, "17,25" in Spanish.
String fieldExact(double? value) => value == null
    ? ''
    : value.isFinite && value == value.truncateToDouble()
    ? value.toInt().toString()
    : fieldDecimal(value.toString());

/// [plain] ("13.33") with the device's decimal separator.
String fieldDecimal(String plain) =>
    plain.replaceAll('.', _fieldFormats.decimal.symbols.DECIMAL_SEP);

String plainNumberText(String text) {
  final symbols = _fieldFormats.decimal.symbols;
  final zero = symbols.ZERO_DIGIT.codeUnitAt(0);
  var plain = text
      .trim()
      .replaceAll(symbols.DECIMAL_SEP, '.')
      .replaceAll(',', '.');
  if (zero != 48) {
    plain = String.fromCharCodes(
      plain.runes.map((r) => r >= zero && r <= zero + 9 ? r - zero + 48 : r),
    );
  }
  return plain;
}

double? parseNumber(String text) => double.tryParse(plainNumberText(text));

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

extension IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// Two related fields side by side, stacked when narrow or at large text.
/// A missing half lets the other take the whole row.
class FieldPair extends StatelessWidget {
  const FieldPair(
    this.first,
    this.second, {
    super.key,
    this.minimumRowWidth = 320,
  });

  final Widget? first;
  final Widget? second;
  final double minimumRowWidth;

  @override
  Widget build(BuildContext context) {
    final (left, right) = (first, second);
    if (left == null) return right ?? const SizedBox.shrink();
    if (right == null) return left;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
        if (largeText || constraints.maxWidth < minimumRowWidth) {
          return Column(children: [left, const SizedBox(height: 20), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
