import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/pour_progress.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class PourBars extends StatefulWidget {
  const PourBars({
    super.key,
    required this.plan,
    this.second = 0,
    this.grams,
    this.showSchedule = true,
  });

  final PourPlan plan;
  final int second;
  final double? grams;
  final bool showSchedule;

  @override
  State<PourBars> createState() => _PourBarsState();
}

class _PourBarsState extends State<PourBars> {
  final _scroll = ScrollController();
  bool _follow = true;
  (int, double, double)? _lastLayout;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _position(int index, double extent, double width) {
    final layout = (index, extent, width);
    if (!_follow || layout == _lastLayout) return;
    _lastLayout = layout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_follow ||
          !_scroll.hasClients ||
          _lastLayout != layout) {
        return;
      }
      final target = (index * extent - 18).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = PourProgress(
      plan: widget.plan,
      second: widget.second,
      grams: widget.grams,
    );
    final steps = widget.plan.steps;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extent = math.max(82.0, 82 * scale);
    final largest = steps.map((step) => step.addGrams).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.pourBars, style: theme.textTheme.titleSmall),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('pour-follow'),
            onPressed: () => setState(() {
              _follow = true;
              _lastLayout = null;
            }),
            icon: Icon(
              _follow ? Icons.my_location : Icons.location_searching,
              size: 18,
            ),
            label: Text(_follow ? s.pourFollowing : s.pourFollow),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            _position(progress.fillingIndex, extent, constraints.maxWidth);
            return NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.direction != ScrollDirection.idle && _follow) {
                  setState(() => _follow = false);
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const ValueKey('pour-bars-scroll'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, step) in steps.indexed)
                      SizedBox(
                        key: ValueKey('pour-bar-$index'),
                        width: extent,
                        child: _PourBar(
                          step: step,
                          showSchedule: widget.showSchedule,
                          largest: largest,
                          filled: progress.filled(step),
                          active: index == progress.fillingIndex,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        if (widget.grams == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.pourNoReading, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _PourBar extends StatelessWidget {
  const _PourBar({
    required this.step,
    required this.largest,
    required this.filled,
    required this.active,
    required this.showSchedule,
  });
  final PourStep step;
  final double largest;
  final double? filled;
  final bool active;
  final bool showSchedule;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final label = step.kind == PourStepKind.bloom
        ? s.bloomNumber(step.number)
        : s.pourNumber(step.number);
    final ratio = filled == null
        ? 0.0
        : (filled! / step.addGrams).clamp(0.0, 1.0);
    final complete = filled != null && ratio >= 1;
    final clock =
        '${step.startSecond ~/ 60}:${(step.startSecond % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label:
          '$label, ${s.pourAdd(number.format(step.addGrams))}, ${s.pourTo(number.format(step.targetGrams))}',
      value: filled == null
          ? s.pourNoReading
          : '${number.format(filled)} / ${number.format(step.addGrams)} g',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Text(
              '${number.format(step.addGrams)} g',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 44,
                  height: math.max(8, 180 * step.addGrams / largest),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: active
                        ? Border.all(color: colors.primary, width: 2)
                        : null,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: ratio,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: active
                              ? colors.primary
                              : colors.primary.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (complete)
                  Icon(Icons.check, size: 14, color: colors.primary),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (showSchedule) Text(clock, style: theme.textTheme.bodySmall),
            Text(
              '→ ${number.format(step.targetGrams)} g',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
