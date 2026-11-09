import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/year_review/year_review_details.dart';
import 'package:holybeans/ui/year_review/year_review_share.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';

Future<void> showYearMoney(BuildContext context, CoffeeYear year) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _YearMoney(year: year),
    );

class _YearMoney extends StatefulWidget {
  const _YearMoney({required this.year});
  final CoffeeYear year;
  @override
  State<_YearMoney> createState() => _YearMoneyState();
}

class _YearMoneyState extends State<_YearMoney> {
  late final stories = moneyStoriesFor(widget.year);
  late YearStory story = stories.first;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<YearStory>(
                      isExpanded: true,
                      value: story,
                      items: [
                        for (final item in stories)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item.label(s)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => story = value);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: s.yearReviewAbout,
                    onPressed: () => showYearDetails(context, widget.year),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ),
            Expanded(
              child: YearStoryView(year: widget.year, story: story),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () =>
                    shareCoffeeYear(context, widget.year, story: story),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(s.yearReviewShareCard),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
