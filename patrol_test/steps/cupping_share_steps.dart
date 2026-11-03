import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/cupping/cupping_share_sheet.dart';
import 'package:patrol/patrol.dart';

Future<void> checkCuppingShare(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final r = JournalRepository(db);
  final before = await r.allBrews();
  Uint8List? exported;
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'share');
    final args = call.arguments as Map<dynamic, dynamic>;
    expect(args['mimeTypes'], ['image/png']);
    exported = await File((args['paths'] as List<dynamic>).single as String)
        .readAsBytes();
    // Keep the actual Android-rendered PNG so it can be inspected on the host.
    await File('${Directory.systemTemp.path}/cupping-share.png')
        .writeAsBytes(exported!);
    return 'dev.fluttercommunity.plus/share/unavailable';
  });
  try {
    await $.tap(find.byKey(const ValueKey('cupping-share')));
    await $.waitUntilVisible(find.byType(CuppingShareSheet));
    final card = find.byKey(const ValueKey('cupping-share-card'));
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Patrol grinder'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('Patrol water')),
      findsOneWidget,
    );
    await $.takeNativeScreenshot('cupping-share-cup-cards');
    await $.tap(find.byKey(const ValueKey('cupping-share-dark')));
    await $.pumpAndSettle();
    await $.scrollUntilVisible(
      finder: find.descendant(of: card, matching: find.text('Aftertaste')),
      view: find
          .descendant(
            of: find.byKey(const ValueKey('cupping-share-preview')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await $.takeNativeScreenshot('cupping-share-score-grid');
    final height = $.tester.getSize(card).height;
    await $.tap(find.byKey(const ValueKey('cupping-share-confirm')));
    for (var attempt = 0; exported == null && attempt < 50; attempt++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(exported, isNotNull);
    final codec = await ui.instantiateImageCodec(exported!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, closeTo(height * 1.5, 1));
    frame.image.dispose();
    codec.dispose();
    expect(await r.allBrews(), before);
    expect(find.byType(CuppingShareSheet), findsNothing);
  } finally {
    messenger.setMockMethodCallHandler(channel, null);
  }
}
