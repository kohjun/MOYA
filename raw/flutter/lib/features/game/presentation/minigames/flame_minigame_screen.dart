import 'dart:async' as async;
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/game_models.dart';
import '../../providers/game_provider.dart';

/// 상자 받기 미니게임 — 5개의 상자를 잡으면 미션 완료.
/// MINIGAME 타입 미션의 수행 화면입니다.
class FlameMinigameScreen extends ConsumerStatefulWidget {
  const FlameMinigameScreen({
    super.key,
    required this.sessionId,
    required this.mission,
  });

  final String sessionId;
  final Mission mission;

  @override
  ConsumerState<FlameMinigameScreen> createState() =>
      _FlameMinigameScreenState();
}

class _FlameMinigameScreenState extends ConsumerState<FlameMinigameScreen> {
  static const int _targetCatches = 5;
  late final _BoxCatchGame _game;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _game = _BoxCatchGame(
      targetCatches: _targetCatches,
      onSuccess: _handleSuccess,
    );
  }

  void _handleSuccess() {
    if (_completed) return;
    _completed = true;
    ref
        .read(gameProvider(widget.sessionId).notifier)
        .completeMission(widget.mission.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('미니게임 성공! 미션 완료'),
        backgroundColor: Color(0xFF22C55E),
        duration: Duration(milliseconds: 1200),
      ));
      Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1535),
        foregroundColor: Colors.white,
        title: Text(widget.mission.title),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1A1535),
            width: double.infinity,
            child: const Text(
              '화면을 좌/우로 드래그해 바구니를 움직여 상자 5개를 받으세요.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => _game.moveBasket(d.delta.dx),
              child: GameWidget(game: _game),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Flame 게임 본체 ────────────────────────────────────────────────────────
class _BoxCatchGame extends FlameGame with HasCollisionDetection {
  _BoxCatchGame({
    required this.targetCatches,
    required this.onSuccess,
  });

  final int targetCatches;
  final VoidCallback onSuccess;

  late final _Basket _basket;
  late final TextComponent _hud;
  int _caught = 0;
  async.Timer? _spawnTimer;
  bool _finished = false;

  @override
  Future<void> onLoad() async {
    // 배경
    add(RectangleComponent(
      size: size,
      paint: Paint()..color = const Color(0xFF0B1020),
      priority: -10,
    ));

    // 바구니 (하단 중앙 스폰)
    _basket = _Basket()
      ..position = Vector2(size.x / 2 - 50, size.y - 60);
    add(_basket);

    // HUD
    _hud = TextComponent(
      text: '0 / $targetCatches',
      position: Vector2(16, 16),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    add(_hud);

    // 상자 스폰 타이머 (0.9초마다)
    _spawnTimer =
        async.Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (_finished) return;
      _spawnBox();
    });
  }

  void _spawnBox() {
    final rng = math.Random();
    final x = rng.nextDouble() * (size.x - 40);
    add(_FallingBox(startPos: Vector2(x, -40)));
  }

  void moveBasket(double deltaX) {
    final maxX = size.x - _basket.size.x;
    final newX = (_basket.position.x + deltaX).clamp(0.0, maxX);
    _basket.position.x = newX;
  }

  void onBoxCaught() {
    if (_finished) return;
    _caught++;
    _hud.text = '$_caught / $targetCatches';
    if (_caught >= targetCatches) {
      _finished = true;
      _spawnTimer?.cancel();
      _spawnTimer = null;
      onSuccess();
    }
  }

  @override
  void onRemove() {
    _spawnTimer?.cancel();
    _spawnTimer = null;
    super.onRemove();
  }
}

// ── 바구니 ────────────────────────────────────────────────────────────────
class _Basket extends RectangleComponent with CollisionCallbacks {
  _Basket()
      : super(
          size: Vector2(100, 22),
          paint: Paint()..color = const Color(0xFF22C55E),
        );

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }
}

// ── 낙하 상자 ─────────────────────────────────────────────────────────────
class _FallingBox extends RectangleComponent
    with CollisionCallbacks, HasGameReference<_BoxCatchGame> {
  _FallingBox({required Vector2 startPos})
      : super(
          size: Vector2(40, 40),
          paint: Paint()..color = const Color(0xFFFFC107),
          position: startPos,
        );

  static const double _fallSpeed = 180;
  bool _removed = false;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y += _fallSpeed * dt;
    if (!_removed && position.y > game.size.y + 40) {
      _removed = true;
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    if (_removed) return;
    if (other is _Basket) {
      _removed = true;
      game.onBoxCaught();
      removeFromParent();
    }
  }
}
