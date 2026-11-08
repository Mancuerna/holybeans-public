import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_recipe_context.dart';
import 'package:holybeans/ui/brews/brew_form_recipes.dart';

BrewReferences references(String id) {
  final brew = Brew(
    recipientIsPortafilter: false,
    id: id,
    coffeeId: id,
    methodName: 'V60',
    isPreGround: false,
    isFavorite: false,
    brewedAtMs: 0,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
  return (favorite: brew, last: brew, newest: brew, lastRated: true);
}

void main() {
  for (final ending in ['newer', 'empty', 'dispose']) {
    test(
      'late advice cannot replace $ending selection or notify after close',
      () async {
        final pending = Completer<BrewReferences>();
        var notifications = 0;
        final state = BrewFormRecipes(
          loadMemory: ({required coffeeId, required methodId}) async => null,
          loadReferences: ({required coffeeId, required methodId}) =>
              coffeeId == 'old'
              ? pending.future
              : Future.value(references(coffeeId)),
          notify: () => notifications++,
        );
        final old = state.loadReferences(coffeeId: 'old', methodId: 'v60');
        if (ending == 'newer') {
          await state.loadReferences(coffeeId: 'new', methodId: 'v60');
        } else if (ending == 'empty') {
          await state.loadReferences(coffeeId: 'old');
        } else {
          state.dispose();
        }
        final before = notifications;
        pending.complete(references('old'));
        await old;
        expect(notifications, before);
        expect(
          state.references?.favorite?.id,
          ending == 'newer' ? 'new' : null,
        );
        if (ending != 'dispose') state.dispose();
      },
    );
  }

  test(
    'recipe memory and advice loads do not invalidate one another',
    () async {
      final advice = Completer<BrewReferences>();
      final memory = Completer<BrewRecipeMemory?>();
      final state = BrewFormRecipes(
        loadMemory: ({required coffeeId, required methodId}) => memory.future,
        loadReferences: ({required coffeeId, required methodId}) =>
            advice.future,
        notify: () {},
      );
      addTearDown(state.dispose);
      final loadingAdvice = state.loadReferences(
        coffeeId: 'a',
        methodId: 'v60',
      );
      BrewRecipeMemory? applied;
      final loadingMemory = state.load(
        coffeeId: 'a',
        methodId: 'v60',
        apply: (value) async => applied = value,
      );
      advice.complete(references('a'));
      await loadingAdvice;
      expect(state.loading, isTrue);
      final saved = (
        brew: references('a').last!,
        favorite: true,
        toolIds: <String>[],
      );
      memory.complete(saved);
      await loadingMemory;
      expect(applied, saved);
      expect(state.memory, saved);
      expect(state.references?.newest?.id, 'a');
      expect(state.loading, isFalse);
    },
  );

  test(
    'a failed advice read clears the previous reference and can retry',
    () async {
      var fail = false;
      final state = BrewFormRecipes(
        loadMemory: ({required coffeeId, required methodId}) async => null,
        loadReferences: ({required coffeeId, required methodId}) async {
          if (fail) throw StateError('read failure');
          return references(coffeeId);
        },
        notify: () {},
      );
      addTearDown(state.dispose);
      await state.loadReferences(coffeeId: 'a', methodId: 'v60');
      fail = true;
      await state.loadReferences(coffeeId: 'b', methodId: 'v60');
      expect(state.references, isNull);
      fail = false;
      await state.loadReferences(coffeeId: 'b', methodId: 'v60');
      expect(state.references?.last?.id, 'b');
    },
  );
}
