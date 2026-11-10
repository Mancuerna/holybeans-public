import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('incoming cards reject private URIs and keep the UI responsive', (
    $,
  ) async {
    final incoming = IncomingShares();
    final semantics = $.tester.ensureSemantics();
    // Exercise the incoming channel independently of app routing.
    final routes = _ChannelRoutes();
    WidgetsBinding.instance.addObserver(routes);
    final received = ValueNotifier<List<String>>([]);
    final subscription = incoming.arrivals.listen(
      (text) => received.value = [...received.value, text],
    );
    final cache = await getTemporaryDirectory();
    final privateFile = File(
      p.join(cache.path, 'clipboard-images', 'probe.json'),
    );
    await privateFile.parent.create(recursive: true);
    await privateFile.writeAsString('{"name":"Private"}');
    var taps = 0;
    try {
      await incoming.takeLaunch();
      await $.pumpWidgetAndSettle(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Incoming cards test')),
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => taps++),
                    child: Text('Tap $taps'),
                  ),
                  ValueListenableBuilder(
                    valueListenable: received,
                    builder: (context, values, child) => Text(
                      values.isEmpty ? 'Empty' : values.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final uri in [
        'holybeans://bean?d=${'A' * 8192}',
        privateFile.uri.toString(),
        'content://com.caffeinateddev.holybeans.patrol.clipboard/images/probe.json',
      ]) {
        await send($, uri);
      }
      // The serial reader makes this valid link a barrier after rejected inputs.
      const valid = 'holybeans://shortcut/beans';
      await send($, valid);
      await $.waitUntilVisible(find.text(valid));
      expect(received.value.length, 1);
      expect(received.value.single, valid);
      await send(
        $,
        'content://com.caffeinateddev.holybeans.patrol.test.incoming/slow',
      );
      await $.platform.android.tap(
        const AndroidSelector(contentDescription: 'Tap 0'),
      );
      await $.pumpAndSettle();
      expect(find.text('Tap 1'), findsOneWidget);
      expect(received.value, [valid]);
      await $.platform.mobile.openUrl('holybeans-incoming-test://release');
      await $.waitUntilVisible(find.text('{"name":"External"}'));
      expect(received.value, [valid, '{"name":"External"}']);
    } finally {
      await $.platform.mobile.openUrl('holybeans-incoming-test://release');
      await $.pumpWidgetAndSettle(const SizedBox.shrink());
      await subscription.cancel();
      incoming.dispose();
      WidgetsBinding.instance.removeObserver(routes);
      semantics.dispose();
      received.dispose();
      await privateFile.delete();
    }
  });
}

class _ChannelRoutes with WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async => true;
}

Future<void> send(PatrolIntegrationTester $, String uri) =>
    $.platform.mobile.openUrl(
      Uri(
        scheme: 'holybeans-incoming-test',
        host: 'send',
        queryParameters: {'uri': uri},
      ).toString(),
    );
