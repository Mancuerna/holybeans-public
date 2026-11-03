import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareCoffeeYear(BuildContext context, CoffeeYear year) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _YearShare(year: year),
    );

class YearSummaryCard extends StatelessWidget {
  const YearSummaryCard({super.key, required this.year});
  final CoffeeYear year;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat.decimalPattern(regionalLocale.toString());
    return SizedBox(
      width: 560,
      child: YearBackdrop(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.yearReviewTitle,
                style: const TextStyle(
                  color: yearWine,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text('${year.year}', style: yearHeadline(112)),
              Text(
                year.isPartial
                    ? s.yearReviewUntil(
                        DateFormat.yMMMd(regionalLocale.toString())
                            .format(year.asOf),
                      )
                    : s.yearReviewComplete,
                style: const TextStyle(color: yearInk, fontSize: 16),
              ),
              const SizedBox(height: 28),
              YearMetric(
                value: number.format(year.count),
                label: s.yearReviewBrews,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: YearMetric(
                      value: number.format(year.coffeeCount),
                      label: s.yearReviewBeans,
                    ),
                  ),
                  Expanded(
                    child: YearMetric(
                      value: number.format(year.activeDays),
                      label: s.yearReviewDays,
                    ),
                  ),
                ],
              ),
              if (year.methodRanks.firstOrNull case final method?) ...[
                const SizedBox(height: 28),
                _SummaryLine(label: s.yearReviewTopMethod, value: method.name),
              ],
              if (year.coffeeRanks.firstOrNull case final coffee?
                  when coffee.name.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SummaryLine(label: s.yearReviewTopCoffee, value: coffee.name),
              ],
              const SizedBox(height: 32),
              const Divider(color: yearWine),
              Text(
                s.yearReviewBrand,
                style: const TextStyle(
                  color: yearWine,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: yearWine, fontSize: 16)),
      Text(
        value,
        style: const TextStyle(
          color: yearInk,
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _YearShare extends StatefulWidget {
  const _YearShare({required this.year});
  final CoffeeYear year;
  @override
  State<_YearShare> createState() => _YearShareState();
}

class _YearShareState extends State<_YearShare> {
  final boundaryKey = GlobalKey();
  bool busy = false;
  Future<void> _share() async {
    setState(() => busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (!mounted || bytes == null) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: ['holybeans-${widget.year.year}.png'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.shareFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(s.yearReviewShareHint),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: YearSummaryCard(year: widget.year),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const ValueKey('year-share-confirm'),
                onPressed: busy ? null : _share,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: Text(s.share),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
