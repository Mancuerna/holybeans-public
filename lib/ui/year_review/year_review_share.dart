import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/year_review/year_review_card.dart';
import 'package:holybeans/ui/year_review/year_review_story.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareCoffeeYear(
  BuildContext context,
  CoffeeYear year, {
  YearStory story = YearStory.finalCard,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _YearShare(year: year, initial: story),
);

class YearExportCard extends StatelessWidget {
  const YearExportCard({super.key, required this.year, required this.story});
  final CoffeeYear year;
  final YearStory story;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: SizedBox(
      width: 360,
      height: 640,
      child: YearStoryCard(year: year, story: story, forExport: true),
    ),
  );
}

class _YearShare extends StatefulWidget {
  const _YearShare({required this.year, required this.initial});
  final CoffeeYear year;
  final YearStory initial;
  @override
  State<_YearShare> createState() => _YearShareState();
}

class _YearShareState extends State<_YearShare> {
  final boundaryKey = GlobalKey();
  late final available = <YearStory>{
    ...storiesFor(widget.year),
    if (moneyStoriesFor(widget.year).contains(widget.initial))
      ...moneyStoriesFor(widget.year),
    widget.initial,
  }.toList();
  late final selected = <YearStory>{widget.initial};
  late YearStory preview = widget.initial;
  bool busy = false;

  Future<void> _share() async {
    final toShare = available.where(selected.contains).toList();
    if (toShare.isEmpty || busy) return;
    final original = preview;
    await Scrollable.ensureVisible(boundaryKey.currentContext!);
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final files = <XFile>[];
      final names = <String>[];
      for (final story in toShare) {
        if (!mounted) return;
        setState(() => preview = story);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        ByteData? bytes;
        try {
          bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
        }
        if (!mounted) return;
        if (bytes == null) throw StateError('Could not encode year card');
        files.add(
          XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png'),
        );
        names.add('holybeans-${widget.year.year}-${story.name}.png');
      }
      if (!mounted) return;
      setState(() => preview = original);
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          fileNameOverrides: names,
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
      if (mounted) {
        setState(() {
          busy = false;
          preview = original;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.yearReviewSelection,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('year-share-all'),
                            tooltip: s.yearReviewSelectAll,
                            onPressed: busy
                                ? null
                                : () => setState(
                                    () => selected.addAll(available),
                                  ),
                            icon: const Icon(Icons.select_all),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(20) + 40,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: available.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final story = available[index];
                          return Center(
                            child: FilterChip(
                              key: ValueKey('year-pick-${story.name}'),
                              label: Text(story.label(s)),
                              selected: selected.contains(story),
                              onSelected: busy
                                  ? null
                                  : (value) => setState(() {
                                      if (value) {
                                        selected.add(story);
                                        preview = story;
                                      } else {
                                        selected.remove(story);
                                        if (selected.isNotEmpty &&
                                            preview == story) {
                                          preview = selected.last;
                                        }
                                      }
                                    }),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: 360,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Center(
                          child: FittedBox(
                            child: RepaintBoundary(
                              key: boundaryKey,
                              child: YearExportCard(
                                year: widget.year,
                                story: preview,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        s.yearReviewShareHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const ValueKey('year-share-confirm'),
                onPressed: busy || selected.isEmpty ? null : _share,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  selected.length <= 1
                      ? s.yearReviewShareCard
                      : s.yearReviewShareCards(selected.length),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
