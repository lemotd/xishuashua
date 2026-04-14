import 'dart:math';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';

const _c = AppColors.dark;

/// Displays comments as scrolling bullet-screen (弹幕) text.
/// Tap a danmaku to pause it, show a delete menu, and optionally
/// delete with a particle-burst animation.
class DanmakuOverlay extends StatefulWidget {
  final String assetId;
  const DanmakuOverlay({super.key, required this.assetId});

  @override
  State<DanmakuOverlay> createState() => DanmakuOverlayState();
}

class DanmakuOverlayState extends State<DanmakuOverlay>
    with TickerProviderStateMixin {
  final List<_DanmakuEntry> _entries = [];
  final List<_ParticleBurst> _bursts = [];
  final _random = Random();
  int _idCounter = 0;
  int? _selectedId;

  static const int _laneCount = 6;
  static const double _topPadding = 100.0;
  static const double _laneHeight = 36.0;

  @override
  void initState() {
    super.initState();
    _launchComments();
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _clearAll();
      _launchComments();
    }
  }

  void _clearAll() {
    _selectedId = null;
    for (final e in _entries) {
      e.controller.dispose();
    }
    _entries.clear();
    for (final b in _bursts) {
      b.controller.dispose();
    }
    _bursts.clear();
  }

  void reload() {
    _clearAll();
    if (mounted) setState(() => _launchComments());
  }

  /// 追加一条新弹幕，不刷新已有的
  void addOne(String text) {
    if (!mounted) return;
    final comments = InteractionService.getComments(widget.assetId);
    final index = comments.length - 1;
    final lane = _random.nextInt(_laneCount);
    _spawnOne(text, lane, index < 0 ? 0 : index);
  }

  void _launchComments() {
    final comments = InteractionService.getComments(widget.assetId);
    if (comments.isEmpty) return;
    for (int i = 0; i < comments.length; i++) {
      final delay = Duration(milliseconds: i * 600 + _random.nextInt(400));
      Future.delayed(delay, () {
        if (!mounted) return;
        _spawnOne(comments[i].text, i % _laneCount, i);
      });
    }
  }

  void _spawnOne(String text, int lane, int commentIndex) {
    final id = _idCounter++;
    final duration = Duration(milliseconds: 6000 + _random.nextInt(3000));
    final ctrl = AnimationController(vsync: this, duration: duration);

    final entry = _DanmakuEntry(
      id: id,
      text: text,
      lane: lane,
      commentIndex: commentIndex,
      controller: ctrl,
    );

    setState(() => _entries.add(entry));

    ctrl.forward().then((_) {
      if (!mounted) return;
      ctrl.dispose();
      setState(() => _entries.removeWhere((e) => e.id == id));
    });
  }

  void _onTapDanmaku(int id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedId == id) {
        // Deselect: resume
        _selectedId = null;
        final entry = _entries.where((e) => e.id == id).firstOrNull;
        entry?.controller.forward();
      } else {
        // Deselect previous
        if (_selectedId != null) {
          final prev = _entries.where((e) => e.id == _selectedId).firstOrNull;
          prev?.controller.forward();
        }
        // Select: pause
        _selectedId = id;
        final entry = _entries.where((e) => e.id == id).firstOrNull;
        entry?.controller.stop();
      }
    });
  }

  void _onDismiss() {
    if (_selectedId == null) return;
    final entry = _entries.where((e) => e.id == _selectedId).firstOrNull;
    if (entry != null) {
      entry.controller.forward();
    }
    setState(() => _selectedId = null);
  }

  void _onDelete(int id) {
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;

    HapticFeedback.mediumImpact();

    // Delete from storage
    InteractionService.removeComment(widget.assetId, entry.commentIndex);

    // Calculate current position for particle burst
    final width = MediaQuery.of(context).size.width;
    final dx = width - entry.controller.value * (width + 300);
    final dy = _topPadding + entry.lane * _laneHeight;

    // Remove the danmaku entry
    entry.controller.dispose();
    setState(() {
      _entries.removeWhere((e) => e.id == id);
      _selectedId = null;
    });

    // Spawn particle burst at the danmaku's position
    _spawnBurst(dx, dy, entry.text);
  }

  void _spawnBurst(double x, double y, String text) {
    final burstId = _idCounter++;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Generate particles
    final particles = List.generate(18, (_) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 40.0 + _random.nextDouble() * 80.0;
      final size = 2.0 + _random.nextDouble() * 4.0;
      return _Particle(
        dx: cos(angle) * speed,
        dy: sin(angle) * speed,
        size: size,
        color: [
          const Color(0xFF6366F1),
          const Color(0xFF8B5CF6),
          const Color(0xFFEC4899),
          const Color(0xFF06B6D4),
          const Color(0xFFF59E0B),
          Colors.white,
        ][_random.nextInt(6)],
      );
    });

    final burst = _ParticleBurst(
      id: burstId,
      x: x,
      y: y,
      particles: particles,
      controller: ctrl,
    );

    setState(() => _bursts.add(burst));

    ctrl.forward().then((_) {
      if (!mounted) return;
      ctrl.dispose();
      setState(() => _bursts.removeWhere((b) => b.id == burstId));
    });
  }

  @override
  void dispose() {
    _clearAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hasSelection = _selectedId != null;

    return Stack(
      children: [
        // Dismiss layer when a danmaku is selected
        if (hasSelection)
          Positioned.fill(
            child: GestureDetector(
              onTap: _onDismiss,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),

        // Danmaku items
        ..._entries.map((entry) {
          final isSelected = entry.id == _selectedId;
          return AnimatedBuilder(
            animation: entry.controller,
            builder: (context, child) {
              final dx = width - entry.controller.value * (width + 300);
              final dy = _topPadding + entry.lane * _laneHeight;
              return Positioned(left: dx, top: dy, child: child!);
            },
            child: GestureDetector(
              onTap: () => _onTapDanmaku(entry.id),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Danmaku capsule
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.6)
                          : Colors.black.withValues(alpha: 0.35),
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 16,
                        cornerSmoothing: 0.6,
                      ),
                      border: isSelected
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Text(
                      entry.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Delete menu
                  _DeleteMenu(
                    visible: isSelected,
                    onDelete: () => _onDelete(entry.id),
                  ),
                ],
              ),
            ),
          );
        }),

        // Particle bursts (non-interactive)
        ..._bursts.map((burst) {
          return IgnorePointer(
            child: AnimatedBuilder(
              animation: burst.controller,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _ParticlePainter(
                    burst: burst,
                    progress: burst.controller.value,
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

// ── Delete menu with slide-up animation ──

class _DeleteMenu extends StatefulWidget {
  final bool visible;
  final VoidCallback onDelete;
  const _DeleteMenu({required this.visible, required this.onDelete});

  @override
  State<_DeleteMenu> createState() => _DeleteMenuState();
}

class _DeleteMenuState extends State<_DeleteMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween(
      begin: -8.0,
      end: 4.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    if (widget.visible) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_DeleteMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _ctrl.forward(from: 0);
    } else if (!widget.visible && oldWidget.visible) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        if (_ctrl.isDismissed) return const SizedBox.shrink();
        return Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: Opacity(opacity: _fadeAnim.value, child: child),
        );
      },
      child: GestureDetector(
        onTap: widget.onDelete,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _c.primary,
            borderRadius: SmoothBorderRadius(
              cornerRadius: 12,
              cornerSmoothing: 0.6,
            ),
          ),
          child: const Text(
            '删除',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data models ──

class _DanmakuEntry {
  final int id;
  final String text;
  final int lane;
  final int commentIndex;
  final AnimationController controller;

  _DanmakuEntry({
    required this.id,
    required this.text,
    required this.lane,
    required this.commentIndex,
    required this.controller,
  });
}

class _ParticleBurst {
  final int id;
  final double x, y;
  final List<_Particle> particles;
  final AnimationController controller;

  _ParticleBurst({
    required this.id,
    required this.x,
    required this.y,
    required this.particles,
    required this.controller,
  });
}

class _Particle {
  final double dx, dy, size;
  final Color color;
  const _Particle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });
}

// ── Particle painter ──

class _ParticlePainter extends CustomPainter {
  final _ParticleBurst burst;
  final double progress;

  _ParticlePainter({required this.burst, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    // Ease out the movement
    final t = Curves.easeOutCubic.transform(progress);

    for (final p in burst.particles) {
      final px = burst.x + p.dx * t;
      final py = burst.y + p.dy * t;
      final s = p.size * (1.0 - progress * 0.5);

      canvas.drawCircle(
        Offset(px, py),
        s,
        Paint()..color = p.color.withValues(alpha: opacity * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
