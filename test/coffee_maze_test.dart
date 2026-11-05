import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/coffee_maze.dart';

void advance(CoffeeMaze game, double seconds) {
  for (var i = 0; i < (seconds * 120).ceil(); i++) {
    game.advance(1 / 120);
  }
}

void quietEnemies(CoffeeMaze game) {
  for (final enemy in game.enemies) {
    enemy.resting = 1000;
  }
}

void main() {
  test('every collectible and spawn is reachable inside the maze', () {
    final game = CoffeeMaze();
    expect(CoffeeMaze.layout.length, CoffeeMaze.rows);
    expect(
      CoffeeMaze.layout.every((row) => row.length == CoffeeMaze.columns),
      isTrue,
    );
    final reached = {CoffeeMaze.playerStart};
    final pending = [CoffeeMaze.playerStart];
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      for (final direction in MazeDirection.values) {
        final next = cell.next(direction);
        if (game.isOpen(next) && reached.add(next)) pending.add(next);
      }
    }
    expect(
      reached,
      containsAll([
        ...game.beans,
        ...game.espressos,
        ...CoffeeMaze.enemyStarts,
      ]),
    );
    for (var x = 0; x < CoffeeMaze.columns; x++) {
      expect(game.isOpen(MazeCell(x, 0)), isFalse);
      expect(game.isOpen(MazeCell(x, CoffeeMaze.rows - 1)), isFalse);
    }
    for (var y = 0; y < CoffeeMaze.rows; y++) {
      expect(game.isOpen(MazeCell(0, y)), isFalse);
      expect(game.isOpen(MazeCell(CoffeeMaze.columns - 1, y)), isFalse);
    }
  });

  test('buffers a turn until a corridor opens and never enters a wall', () {
    final game = CoffeeMaze()..start();
    quietEnemies(game);
    game.player = MazeActor(const MazeCell(1, 1))
      ..destination = const MazeCell(2, 1)
      ..progress = .5
      ..direction = MazeDirection.right;
    game.steer(MazeDirection.down);
    advance(game, .7);
    expect(game.player.x, 4);
    expect(game.player.y, greaterThan(1));
    advance(game, 5);
    expect(game.isOpen(game.player.cell), isTrue);
    expect(game.isOpen(game.player.destination), isTrue);
    expect(game.player.y, 5);
  });

  test('reverses immediately without teleporting between cells', () {
    final game = CoffeeMaze()..start();
    quietEnemies(game);
    advance(game, .1);
    final x = game.player.x;
    game.steer(MazeDirection.right);
    expect(game.player.x, closeTo(x, .00001));
    advance(game, .05);
    expect(game.player.x, greaterThan(x));
  });

  test('beans score once and espresso enables eating a spirit', () {
    final game = CoffeeMaze()..start();
    quietEnemies(game);
    advance(game, .22);
    expect(game.score, 10);
    game.steer(MazeDirection.right);
    advance(game, .22);
    game.steer(MazeDirection.left);
    advance(game, .22);
    expect(game.score, 10);
    game.player = MazeActor(const MazeCell(2, 1));
    game.steer(MazeDirection.left);
    advance(game, .22);
    expect(game.score, 60);
    expect(game.caffeine, greaterThan(6));
    game.enemies[0] = MazeActor(game.player.cell);
    advance(game, .01);
    expect(game.score, 260);
    expect(game.lives, 3);
    expect(game.enemies[0].resting, greaterThan(0));
    advance(game, 7.1);
    expect(game.caffeine, 0);
  });

  test(
    'crossing actors collide, lose one life and preserve collected beans',
    () {
      final game = CoffeeMaze()..start();
      quietEnemies(game);
      advance(game, .22);
      final remaining = game.beans.length;
      game.protection = 0;
      game.player = MazeActor(const MazeCell(8, 9))
        ..direction = MazeDirection.right;
      game.steer(MazeDirection.right);
      game.enemies[0] = MazeActor(const MazeCell(9, 9));
      advance(game, .2);
      expect(game.phase, MazePhase.caught);
      expect(game.lives, 2);
      advance(game, 2);
      expect(game.lives, 2);
      game.start();
      expect(game.player.cell, CoffeeMaze.playerStart);
      expect(game.beans.length, remaining);
      expect(game.protection, greaterThan(0));
    },
  );

  test('three collisions end the round; another cup resets the run', () {
    final game = CoffeeMaze()..start();
    for (var life = 0; life < 3; life++) {
      game.protection = 0;
      game.enemies[0] = MazeActor(game.player.cell);
      advance(game, .01);
      expect(game.lives, 2 - life);
      if (life < 2) game.start();
    }
    expect(game.phase, MazePhase.over);
    game.start();
    expect(game.phase, MazePhase.playing);
    expect(game.lives, 3);
    expect(game.score, 0);
    expect(game.level, 1);
  });

  test('last bean grants a bonus; next round refills and speeds up', () {
    final game = CoffeeMaze()..start();
    quietEnemies(game);
    game.beans
      ..clear()
      ..add(const MazeCell(8, 15));
    game.espressos.clear();
    final initialSpeed = game.speed;
    advance(game, .22);
    expect(game.phase, MazePhase.cleared);
    expect(game.score, 510);
    game.start();
    expect(game.level, 2);
    expect(game.score, 510);
    expect(game.speed, greaterThan(initialSpeed));
    expect(game.beans, isNotEmpty);
    expect(game.espressos.length, 4);
  });

  test('pause freezes positions and timers; a delayed frame is bounded', () {
    final game = CoffeeMaze()..start();
    quietEnemies(game);
    game.caffeine = 6;
    advance(game, .1);
    game.pause();
    final before = (game.player.x, game.player.y, game.caffeine, game.elapsed);
    advance(game, 10);
    expect((game.player.x, game.player.y, game.caffeine, game.elapsed), before);
    game.start();
    final time = game.elapsed;
    game.advance(60);
    expect(game.elapsed - time, lessThanOrEqualTo(.101));
  });

  test('simulation behaves consistently at different refresh rates', () {
    CoffeeMaze run(int hz) {
      final game = CoffeeMaze()..start();
      quietEnemies(game);
      for (var frame = 0; frame < hz; frame++) {
        game.advance(1 / hz);
      }
      return game;
    }

    final slow = run(30);
    final fast = run(120);
    expect(slow.player.x, closeTo(fast.player.x, .05));
    expect(slow.score, fast.score);
  });
}
