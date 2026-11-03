import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/core/photos_draft.dart';

void main() {
  late Directory temp;
  late PhotoStore store;
  late PhotosDraft draft;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('holybeans-draft-');
    store = PhotoStore(temp);
    draft = PhotosDraft(store);
  });
  tearDown(() async {
    // Tests that exercise disposal own it themselves.
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test(
    'a pending selection appends to the latest list, not removed photos',
    () async {
      final first = await store.add(Uint8List.fromList([1]));
      final second = await store.add(Uint8List.fromList([2]));
      draft.set([first]);
      final selection = Completer<String?>();
      final pending = draft.pick(() => selection.future);
      draft.set([]);
      selection.complete(second);
      expect(await pending, isTrue);
      expect(draft.current, [second]);
      await draft.commit();
      expect(store.file(first).existsSync(), isFalse);
      expect(store.file(second).existsSync(), isTrue);
      draft.dispose();
    },
  );

  test('concurrent picks do not open a second selector', () async {
    final selection = Completer<String?>();
    final pending = draft.pick(() => selection.future);
    var secondOpened = false;
    expect(
      await draft.pick(() async {
        secondOpened = true;
        return null;
      }),
      isFalse,
    );
    expect(secondOpened, isFalse);
    expect(draft.picking, isTrue);
    selection.complete(null);
    await pending;
    expect(draft.picking, isFalse);
    draft.dispose();
  });

  test('a late completion after disposal deletes its owned file', () async {
    final selection = Completer<String?>();
    final pending = draft.pick(() => selection.future);
    draft.dispose();
    final name = await store.add(Uint8List.fromList([3]));
    selection.complete(name);
    expect(await pending, isFalse);
    expect(store.file(name).existsSync(), isFalse);
  });

  test('selection error unlocks the draft and a later pick succeeds', () async {
    await expectLater(
      draft.pick(() async => throw StateError('Picker failure')),
      throwsStateError,
    );
    expect(draft.picking, isFalse);
    final name = await store.add(Uint8List.fromList([4]));
    expect(await draft.pick(() async => name), isTrue);
    await draft.commit();
    draft.dispose();
  });

  test(
    'save cannot begin during a pick and picking is blocked during saving',
    () async {
      final selection = Completer<String?>();
      final pending = draft.pick(() => selection.future);
      expect(draft.beginSave, throwsStateError);
      selection.complete(null);
      await pending;
      draft.beginSave();
      expect(
        await draft.pick(() async => throw StateError('Must not open')),
        isFalse,
      );
      draft.endSave();
      expect(draft.locked, isFalse);
      await draft.commit();
      expect(
        await draft.pick(() async => throw StateError('Already saved')),
        isFalse,
      );
      draft.dispose();
    },
  );

  test(
    'late selections over the limit are cleaned without losing current photos',
    () async {
      final selection = Completer<String?>();
      final pending = draft.pick(() => selection.future, limit: 1);
      final current = await store.add(Uint8List.fromList([5]));
      final late = await store.add(Uint8List.fromList([6]));
      draft.set([current]);
      selection.complete(late);
      expect(await pending, isFalse);
      expect(draft.current, [current]);
      expect(store.file(late).existsSync(), isFalse);
      await draft.commit();
      draft.dispose();
    },
  );
  test(
    'disposal during a successful save retains its persisted photo',
    () async {
      final name = await store.add(Uint8List.fromList([7]));
      draft.set([name]);
      draft.beginSave();
      draft.dispose();
      await draft.commit();
      draft.endSave();
      expect(store.file(name).existsSync(), isTrue);
    },
  );
}
