import 'dart:collection';
import 'dart:math' as math;

enum MazeDirection {
  up(0, -1),
  left(-1, 0),
  down(0, 1),
  right(1, 0);

  const MazeDirection(this.dx, this.dy);
  final int dx;
  final int dy;

  MazeDirection get opposite => values[(index + 2) % 4];
}

enum MazePhase { ready, playing, paused, caught, cleared, over }

class MazeCell {
  const MazeCell(this.x, this.y);
  final int x;
  final int y;

  MazeCell next(MazeDirection direction) =>
      MazeCell(x + direction.dx, y + direction.dy);

  @override
  bool operator ==(Object other) =>
      other is MazeCell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class MazeActor {
  MazeActor(this.cell) : destination = cell;

  MazeCell cell;
  MazeCell destination;
  MazeDirection direction = MazeDirection.left;
  double progress = 0;
  double resting = 0;

  double get x => cell.x + (destination.x - cell.x) * progress;
  double get y => cell.y + (destination.y - cell.y) * progress;
}

class CoffeeMaze {
  CoffeeMaze() {
    _fill();
    _placeActors();
  }

  static const layout = [
    '###################',
    '#o....#.....#....o#',
    '#.##.#.#.#.#.#.##.#',
    '#....#...#...#....#',
    '#.##.###.#.###.##.#',
    '#.................#',
    '###.#.##.#.##.#.###',
    '#...#....#....#...#',
    '#.#####.#.#.#####.#',
    '#.......   .......#',
    '#.###.#.###.#.###.#',
    '#.....#.....#.....#',
    '#.###.###.###.###.#',
    '#...#.........#...#',
    '###.#.#.###.#.#.###',
    '#.....#.. ..#.....#',
    '#.###.##.#.##.###.#',
    '#o..#....#....#..o#',
    '#.#.#.##.#.##.#.#.#',
    '#.................#',
    '###################',
  ];
  static const columns = 19;
  static const rows = 21;
  static const playerStart = MazeCell(9, 15);
  static const enemyStarts = [MazeCell(8, 9), MazeCell(9, 9), MazeCell(10, 9)];

  final beans = <MazeCell>{};
  final espressos = <MazeCell>{};
  late MazeActor player;
  final enemies = <MazeActor>[];
  MazePhase phase = MazePhase.ready;
  MazeDirection queuedDirection = MazeDirection.left;
  int score = 0;
  int lives = 3;
  int level = 1;
  double caffeine = 0;
  double protection = 0;
  double elapsed = 0;
  double _remainder = 0;

  double get speed => 5 + math.min(level - 1, 8) * .22;

  bool isOpen(MazeCell cell) =>
      cell.x >= 0 &&
      cell.x < columns &&
      cell.y >= 0 &&
      cell.y < rows &&
      layout[cell.y][cell.x] != '#';

  void _fill() {
    beans.clear();
    espressos.clear();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if (layout[y][x] == '.') beans.add(MazeCell(x, y));
        if (layout[y][x] == 'o') espressos.add(MazeCell(x, y));
      }
    }
  }

  void _placeActors() {
    player = MazeActor(playerStart);
    enemies
      ..clear()
      ..addAll(enemyStarts.map(MazeActor.new));
    for (var i = 0; i < enemies.length; i++) {
      enemies[i].resting = 1 + i * .7;
    }
    queuedDirection = MazeDirection.left;
    caffeine = 0;
    protection = 2;
    _remainder = 0;
  }

  void start() {
    if (phase == MazePhase.playing) return;
    if (phase == MazePhase.over) {
      score = 0;
      lives = 3;
      level = 1;
      elapsed = 0;
      _fill();
      _placeActors();
    } else if (phase == MazePhase.cleared) {
      level++;
      _fill();
      _placeActors();
    } else if (phase == MazePhase.caught) {
      _placeActors();
    }
    phase = MazePhase.playing;
  }

  void pause() {
    if (phase == MazePhase.playing) phase = MazePhase.paused;
  }

  void steer(MazeDirection direction) {
    queuedDirection = direction;
    if (phase == MazePhase.playing &&
        direction == player.direction.opposite &&
        player.cell != player.destination) {
      final previous = player.cell;
      player.cell = player.destination;
      player.destination = previous;
      player.progress = 1 - player.progress;
      player.direction = direction;
    }
  }

  void advance(double seconds) {
    if (phase != MazePhase.playing || !seconds.isFinite || seconds <= 0) return;
    // Ignore time spent suspended; fixed steps also prevent crossing collisions.
    _remainder += math.min(seconds, .1);
    const step = 1 / 120;
    while (_remainder >= step && phase == MazePhase.playing) {
      _remainder -= step;
      _step(step);
    }
  }

  void _step(double dt) {
    elapsed += dt;
    caffeine = math.max(0, caffeine - dt);
    protection = math.max(0, protection - dt);
    _move(player, speed * dt, () {
      if (isOpen(player.cell.next(queuedDirection))) {
        player.direction = queuedDirection;
      }
      return player.direction;
    }, _collect);
    // A last bean can share a cell with an enemy: the collision wins.
    _collisions();
    if (phase != MazePhase.playing) return;
    for (var i = 0; i < enemies.length; i++) {
      final enemy = enemies[i];
      if (enemy.resting > 0) {
        enemy.resting = math.max(0, enemy.resting - dt);
        continue;
      }
      final enemySpeed = speed * (caffeine > 0 ? .52 : .77 + i * .035);
      _move(enemy, enemySpeed * dt, () => _chooseDirection(enemy, i), () {});
    }
    _collisions();
    if (phase == MazePhase.playing && beans.isEmpty && espressos.isEmpty) {
      score += 500;
      phase = MazePhase.cleared;
    }
  }

  void _move(
    MazeActor actor,
    double distance,
    MazeDirection Function() choose,
    void Function() arrived,
  ) {
    while (distance > 0) {
      if (actor.cell == actor.destination) {
        actor.direction = choose();
        final next = actor.cell.next(actor.direction);
        if (!isOpen(next)) return;
        actor.destination = next;
      }
      final remaining = 1 - actor.progress;
      if (distance < remaining) {
        actor.progress += distance;
        return;
      }
      distance -= remaining;
      actor.cell = actor.destination;
      actor.progress = 0;
      arrived();
    }
  }

  void _collect() {
    if (beans.remove(player.cell)) score += 10;
    if (espressos.remove(player.cell)) {
      score += 50;
      caffeine = 7;
    }
  }

  void _collisions() {
    for (var i = 0; i < enemies.length; i++) {
      final enemy = enemies[i];
      if (enemy.resting > 0) continue;
      final dx = player.x - enemy.x;
      final dy = player.y - enemy.y;
      if (dx * dx + dy * dy > .5 * .5) continue;
      if (caffeine > 0) {
        score += 200;
        enemies[i] = MazeActor(enemyStarts[i])..resting = 2;
      } else if (protection <= 0) {
        lives--;
        phase = lives == 0 ? MazePhase.over : MazePhase.caught;
        return;
      }
    }
  }

  MazeDirection _chooseDirection(MazeActor enemy, int index) {
    final options = MazeDirection.values
        .where((direction) => isOpen(enemy.cell.next(direction)))
        .toList();
    if (options.length > 1) options.remove(enemy.direction.opposite);
    var target = player.cell;
    if (index == 1) {
      // The second spirit aims ahead, while the third periodically patrols.
      for (var i = 0; i < 3; i++) {
        final ahead = target.next(player.direction);
        if (isOpen(ahead)) target = ahead;
      }
    } else if (index == 2 && elapsed % 12 < 5) {
      target = const MazeCell(17, 19);
    }
    final distances = _distances(target);
    options.sort((a, b) {
      final da = distances[enemy.cell.next(a)] ?? 999;
      final db = distances[enemy.cell.next(b)] ?? 999;
      final comparison = caffeine > 0 ? db.compareTo(da) : da.compareTo(db);
      return comparison != 0 ? comparison : a.index.compareTo(b.index);
    });
    return options.isEmpty ? enemy.direction : options.first;
  }

  Map<MazeCell, int> _distances(MazeCell target) {
    final distances = <MazeCell, int>{target: 0};
    final queue = Queue<MazeCell>()..add(target);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      for (final direction in MazeDirection.values) {
        final next = cell.next(direction);
        if (isOpen(next) && !distances.containsKey(next)) {
          distances[next] = distances[cell]! + 1;
          queue.add(next);
        }
      }
    }
    return distances;
  }
}
