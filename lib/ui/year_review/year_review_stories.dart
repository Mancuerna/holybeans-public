import 'package:flutter/material.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/domain/coffee_year_inputs.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/year_review/year_review_card.dart';
import 'package:holybeans/ui/year_review/year_review_story.dart';

export 'year_review_story.dart';

class YearStoryView extends StatelessWidget {
  const YearStoryView({
    super.key,
    required this.year,
    required this.story,
    this.photos,
    this.photoOf,
  });
  final CoffeeYear year;
  final YearStory story;
  final PhotoStore? photos;
  final Future<String?> Function(YearBrew)? photoOf;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: PageStorageKey('year-story-${year.year}-${story.name}'),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: YearStoryCard(
          year: year,
          story: story,
          photo: story == YearStory.best && photos != null && photoOf != null
              ? _YearPhoto(
                  key: ValueKey(year.rated.first.id),
                  brew: year.rated.first,
                  photos: photos!,
                  photoOf: photoOf!,
                )
              : null,
        ),
      ),
    ),
  );
}

class _YearPhoto extends StatefulWidget {
  const _YearPhoto({
    super.key,
    required this.brew,
    required this.photos,
    required this.photoOf,
  });
  final YearBrew brew;
  final PhotoStore photos;
  final Future<String?> Function(YearBrew) photoOf;
  @override
  State<_YearPhoto> createState() => _YearPhotoState();
}

class _YearPhotoState extends State<_YearPhoto> {
  late final name = widget.photoOf(widget.brew);
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: name,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null || !PhotoStore.isValidName(file)) {
        return const SizedBox.shrink();
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.file(
          widget.photos.file(file),
          width: double.infinity,
          height: 230,
          fit: BoxFit.cover,
          cacheWidth: 800,
          semanticLabel: AppLocalizations.of(context)!.yearReviewPhoto,
          errorBuilder: (_, error, stack) => const SizedBox.shrink(),
        ),
      );
    },
  );
}
