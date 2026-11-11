import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/year_review/year_review_data.dart';
import 'package:holybeans/ui/year_review/year_review_details.dart';
import 'package:holybeans/ui/year_review/year_review_money.dart';
import 'package:holybeans/ui/year_review/year_review_share.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';
import 'package:holybeans/ui/year_review/year_review_style.dart';

class YearReviewPage extends StatefulWidget {
  const YearReviewPage({
    super.key,
    required this.brews,
    required this.coffees,
    required this.components,
    required this.methods,
    this.lots = const [],
    this.now,
    this.initialYear,
    this.photos,
    this.photoOf,
  });
  final List<CoffeeLot> lots;
  final List<Brew> brews;
  final List<Coffee> coffees;
  final List<CoffeeComponent> components;
  final List<BrewMethod> methods;
  final DateTime? now;
  final int? initialYear;
  final PhotoStore? photos;
  final Future<String?> Function(Brew)? photoOf;
  @override
  State<YearReviewPage> createState() => _YearReviewPageState();
}

class _YearReviewPageState extends State<YearReviewPage> {
  final controller = PageController();
  late DateTime now;
  late List<int> years;
  CoffeeYear? _review;
  late int selectedYear;
  bool updating = false;
  Object? error;
  int _requestVersion = 0;
  (YearReviewRequest, int)? _pending;
  bool _running = false;
  late List<YearStory> stories;
  int page = 0;
  @override
  void initState() {
    super.initState();
    now = widget.now ?? DateTime.now();
    years = coffeeYears(yearJournalDates(widget.brews, widget.lots), now);
    if (years.isEmpty) years = [now.year];
    _load(
      years.contains(widget.initialYear) ? widget.initialYear! : years.first,
    );
  }

  void _load(int year) {
    selectedYear = year;
    error = null;
    final version = ++_requestVersion;
    final request = (
      year: year,
      now: now,
      lots: widget.lots,
      brews: widget.brews,
      coffees: widget.coffees,
      components: widget.components,
      methods: widget.methods,
    );
    updating = widget.brews.length > 200;
    if (updating) {
      _pending = (request, version);
      if (!_running) unawaited(_drain());
    } else {
      _pending = null;
      _accept(prepareYearReview(request));
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (mounted && _pending != null) {
        final (request, version) = _pending!;
        _pending = null;
        try {
          final result = await compute(
            prepareYearReview,
            request,
            debugLabel: 'journal-year-review',
          );
          if (!mounted || version != _requestVersion) continue;
          setState(() {
            updating = false;
            _accept(result);
          });
        } catch (failure, stack) {
          if (!mounted || version != _requestVersion) continue;
          reportError(failure, stack);
          setState(() {
            updating = false;
            error = failure;
          });
        }
      }
    } finally {
      _running = false;
    }
  }

  void _accept(CoffeeYear result) {
    if (controller.hasClients) controller.jumpToPage(0);
    _review = result;
    stories = storiesFor(result);
    page = 0;
  }

  @override
  void dispose() {
    _pending = null;
    controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(index);
    } else {
      controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final review = _review;
    if (review == null) {
      return Scaffold(
        backgroundColor: yearPaper,
        appBar: AppBar(title: Text(s.yearReviewTitle)),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator(key: ValueKey('year-preparing'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.dataError, key: const ValueKey('year-review-error')),
                    TextButton(
                      onPressed: () => setState(() => _load(selectedYear)),
                      child: Text(s.retry),
                    ),
                  ],
                ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: yearPaper,
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(16) > 22
            ? 112
            : 64,
        backgroundColor: yearPaper,
        foregroundColor: yearInk,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.yearReviewTitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            error == null ? 4 : MediaQuery.textScalerOf(context).scale(40),
          ),
          child: error != null
              ? Semantics(
                  liveRegion: true,
                  child: Text(
                    s.dataError,
                    key: const ValueKey('year-review-error'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : SizedBox(
                  height: 4,
                  child: updating ? const LinearProgressIndicator() : null,
                ),
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('year-menu'),
            enabled: !updating && error == null,
            tooltip: s.yearReviewAbout,
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'about') {
                showYearDetails(context, review);
              } else {
                showYearMoney(context, review);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'about', child: Text(s.yearReviewAbout)),
              if (moneyStoriesFor(review).isNotEmpty)
                PopupMenuItem(value: 'money', child: Text(s.yearReviewMoney)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 112,
              child: Tooltip(
                message: s.yearReviewYear,
                child: DropdownButton<int>(
                  isExpanded: true,
                  key: const ValueKey('year-selector'),
                  value: selectedYear,
                  dropdownColor: yearPaper,
                  style: const TextStyle(
                    fontFamily: 'Plex',
                    color: yearWine,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final year in years)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (year) {
                    if (year == null || year == selectedYear) return;
                    setState(() => _load(year));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                children: [
                  Text(
                    '${page + 1} / ${stories.length}',
                    style: const TextStyle(fontSize: 12, color: yearWine),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    label: s.yearReviewProgress(page + 1, stories.length),
                    child: Row(
                      children: [
                        for (var i = 0; i < stories.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i <= page
                                      ? yearWine
                                      : yearWine.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: ValueKey('year-pages-${review.year}'),
                controller: controller,
                itemCount: stories.length,
                onPageChanged: (index) => setState(() => page = index),
                itemBuilder: (context, index) => YearStoryView(
                  year: review,
                  story: stories[index],
                  photos: widget.photos,
                  photoOf: widget.photoOf == null
                      ? null
                      : (brew) => widget.photoOf!(
                          widget.brews.firstWhere(
                            (entry) => entry.id == brew.id,
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('year-previous'),
                    tooltip: s.yearReviewPrevious,
                    onPressed: page > 0 ? () => _go(page - 1) : null,
                    // Faded on the first story, where there is no going back.
                    style: IconButton.styleFrom(
                      foregroundColor: yearWine,
                      disabledForegroundColor: yearWine.withValues(alpha: .3),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('year-share'),
                      style: FilledButton.styleFrom(
                        backgroundColor: yearWine,
                        foregroundColor: yearPaper,
                      ),
                      onPressed:
                          updating ||
                              error != null ||
                              (review.count == 0 &&
                                  review.costs.costedCoffees == 0)
                          ? null
                          : () => shareCoffeeYear(
                              context,
                              review,
                              story: stories[page],
                            ),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text(s.yearReviewShareCard),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('year-next'),
                    tooltip: page == stories.length - 1
                        ? s.yearReviewAgain
                        : s.yearReviewNext,
                    onPressed: () =>
                        _go(page == stories.length - 1 ? 0 : page + 1),
                    color: yearWine,
                    icon: Icon(
                      page == stories.length - 1
                          ? Icons.replay_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
