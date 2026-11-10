import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/ui/core/photo_source_sheet.dart';
import 'package:image_picker/image_picker.dart';

Future<void> _decodePhoto(BuildContext context, Uint8List bytes) async {
  Object? failure;
  await precacheImage(
    MemoryImage(bytes),
    context,
    onError: (error, stack) => failure = error,
  );
  if (failure != null) throw Exception(failure);
}

Future<Uint8List?> pickSharePhoto(BuildContext context) async {
  final source = await choosePhotoSource(context);
  if (source == null || !context.mounted) return null;
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  if (picked == null) return null;
  try {
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    await _decodePhoto(context, bytes);
    return bytes;
  } finally {
    if (source == ImageSource.camera) {
      try {
        await File(picked.path).delete();
      } catch (error, stack) {
        reportError(error, stack);
      }
    }
  }
}

Future<Uint8List?> renderShareImage(
  BuildContext context,
  GlobalKey key, {
  Uint8List? photo,
}) async {
  if (photo != null) {
    await _decodePhoto(context, photo);
    await WidgetsBinding.instance.endOfFrame;
  }
  if (!context.mounted) return null;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
