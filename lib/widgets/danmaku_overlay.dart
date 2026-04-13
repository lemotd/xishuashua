import 'dart:math';
import 'package:flutter/material.dart';
import '../services/interaction_service.dart';

/// Displays comments as scrolling bullet-screen (弹幕) text.
/// Shows automatically when there are comments for the given asset.
class DanmakuOverlay extends StatefulWidget {
  final String assetId;

  const DanmakuOverlay({super.key, required this.assetId});

  @override
  State<DanmakuOverlay> createState() => DanmakuOverlayState();
}

class DanmakuOverlayState extends State<DanmakuOverlay>
    with TickerProviderStateMixin {
  final List<_DanmakuEntry> _entries = [];
  final _random = Random();
  int _idCounter = 0;

  /// Number of horizontal lanes for staggering comments vertically.
  static const int _laneCount = 6;

  /// Top padding so danmaku doesn't overlap the status bar / app bar.
  static const double _topPadding = 100.0;

  /// Vertical spacing between lanes.
  static const double _laneHeight = 36.0;

  @override
  void initState() {
    super.initState();
    _launchComments();
  }

  @override
  void didUpdateWidget(DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId) {
      _clearAll();
      _launchComments();
    }
  }

  void _clearAll() {
    for (final e in _entries) {
      e.controller.dispose();
    }
    _entries.clear();
  }

  /// Reload and re-launch danmaku (called after a new comment is posted).
  void reload() {
    _clearAll();
    if (mounted) _launchComments();
  }

  void _launchComments() {
    final comments = InteractionService.getComments(widget.assetId);
    if (comments.isEmpty) return;

    // Stagger launch so they don't all appear at once.
    for (int i = 0; i < comments.length; i++) {
      final delay = Duration(milliseconds: i * 600 + _random.nextInt(400));
      Future.delayed(delay, () {
        if (!mounted) return;
        _spawnOne(comments[i].text, i % _laneCount);
      });
    }
  }

  void _spawnOne(String text, int lane) {
    final id = _idCounter++;
    final duration = Duration(milliseconds: 6000 + _random.nextInt(3000));
    final ctrl = AnimationController(vsync: this, duration: duration);

    final entry = _DanmakuEntry(
      id: id,
      text: text,
      lane: lane,
      controller: ctrl,
    );

    setState(() => _entries.add(entry));

    ctrl.forward().then((_) {
      if (!mounted) return;
      ctrl.dispose();
      setState(() => _entries.removeWhere((e) => e.id == id));
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

    return IgnorePointer(
      child: Stack(
        children: _entries.map((entry) {
          return AnimatedBuilder(
            animation: entry.controller,
            builder: (context, child) {
              // Slide from right edge to left edge
              final dx = width - entry.controller.value * (width + 300);
              final dy = _topPadding + entry.lane * _laneHeight;
              return Positioned(left: dx, top: dy, child: child!);
            },
            child: _DanmakuText(text: entry.text),
          );
        }).toList(),
      ),
    );
  }
}

class _DanmakuEntry {
  final int id;
  final String text;
  final int lane;
  final AnimationController controller;

  _DanmakuEntry({
    required this.id,
    required this.text,
    required this.lane,
    required this.controller,
  });
}

class _DanmakuText extends StatelessWidget {
  final String text;
  const _DanmakuText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          shadows: [Shadow(color: Color(0x99000000), blurRadius: 4)],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
