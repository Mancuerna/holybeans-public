import 'dart:io';

import 'package:flutter/material.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/motion.dart';
import 'package:holybeans/ui/core/photo_source_sheet.dart';
import 'package:holybeans/ui/core/photos_draft.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo from the camera or gallery, resized to at most 1600 px as a
/// JPEG, and stores it. Returns the new file name, or null when cancelled.
Future<String?> pickPhoto(BuildContext context, PhotoStore store) async {
  final source = await choosePhotoSource(context);
  if (source == null || !context.mounted) return null;
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 82,
  );
  if (picked == null) return null;
  return store.add(await picked.readAsBytes());
}

/// Form control for a list of photos: thumbnails, each with a remove
/// button, and a tile to add another. The first photo is the cover.
class PhotosField extends StatelessWidget {
  const PhotosField({
    super.key,
    required this.store,
    required this.draft,
    required this.label,
    this.maxPhotos = 8,
  });

  final PhotoStore store;
  final PhotosDraft draft;
  final String label;
  final int maxPhotos;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final files = draft.current;
    Future<void> pick() async {
      try {
        await draft.pick(() => pickPhoto(context, store), limit: maxPhotos);
      } catch (error, stack) {
        reportError(error, stack);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(s.photoFailed)));
        }
      }
    }

    if (files.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('add-photo'),
          onPressed: draft.picking || draft.locked ? null : pick,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(s.addPhoto),
        ),
      );
    }
    const size = 72.0;
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (index, name) in files.indexed)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      store.file(name),
                      key: ValueKey('photo-thumb-$name'),
                      width: size,
                      height: size,
                      // Decode at display size, not the stored 1600 px.
                      cacheWidth: cacheWidth,
                      fit: BoxFit.cover,
                      semanticLabel: index == 0
                          ? s.coverPhoto(label)
                          : s.photoNumber(label, index + 1),
                      errorBuilder: (_, _, _) => const SizedBox.square(
                        dimension: size,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: -10,
                    end: -10,
                    child: IconButton.filledTonal(
                      key: ValueKey('remove-photo-$name'),
                      tooltip: s.removePhoto,
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: () =>
                          draft.set([...draft.current]..remove(name)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            if (files.length < maxPhotos)
              SizedBox.square(
                dimension: size,
                child: OutlinedButton(
                  key: const ValueKey('add-photo'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: draft.picking || draft.locked ? null : pick,
                  child: Semantics(
                    label: s.addPhoto,
                    child: const Icon(Icons.add_a_photo_outlined),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Photos at the top of a detail sheet, swiped one by one; tapping opens
/// them full screen.
class DetailPhotos extends StatefulWidget {
  const DetailPhotos({
    super.key,
    required this.store,
    required this.files,
    required this.label,
  });

  final PhotoStore store;
  final List<String> files;
  final String label;

  @override
  State<DetailPhotos> createState() => _DetailPhotosState();
}

class _DetailPhotosState extends State<DetailPhotos> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final files = widget.files;
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final count = files.length;
    return Semantics(
      button: true,
      label: count == 1
          ? widget.label
          : s.photoCount(widget.label, page + 1, count),
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('detail-photo'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _FullScreenPhotos(
              files: [for (final name in files) widget.store.file(name)],
              initialPage: page,
              label: widget.label,
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView(
                  onPageChanged: (value) => setState(() => page = value),
                  children: [
                    for (final name in files)
                      Image.file(
                        widget.store.file(name),
                        cacheWidth: cacheWidth,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                  ],
                ),
                if (count > 1)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: _PageDots(count: count, page: page),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page});

  final int count;
  final int page;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: motionDuration(context, const Duration(milliseconds: 200)),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == page ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: i == page ? 0.95 : 0.6),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
        ),
    ],
  );
}

class _FullScreenPhotos extends StatefulWidget {
  const _FullScreenPhotos({
    required this.files,
    required this.initialPage,
    required this.label,
  });

  final List<File> files;
  final int initialPage;
  final String label;

  @override
  State<_FullScreenPhotos> createState() => _FullScreenPhotosState();
}

class _FullScreenPhotosState extends State<_FullScreenPhotos> {
  late final controller = PageController(initialPage: widget.initialPage);
  late int page = widget.initialPage;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.files.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          count == 1 ? widget.label : '${widget.label} ${page + 1}/$count',
        ),
      ),
      body: PageView(
        controller: controller,
        onPageChanged: (value) => setState(() => page = value),
        children: [
          for (final file in widget.files)
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(file, semanticLabel: widget.label),
              ),
            ),
        ],
      ),
    );
  }
}
