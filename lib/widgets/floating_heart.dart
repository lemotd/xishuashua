import 'dart:math';
import 'package:flutter/material.dart';
import '../color/app_colors.dart';

const _c = AppColors.dark;

class FloatingHeart extends StatefulWidget {
  final Offset position;
  final VoidCallback onComplete;

  const FloatingHeart({
    super.key,
    required this.position,
    required this.onComplete,
  });

  @override
  State<FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<FloatingHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<double> _translateY;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    final random = Random();
    final rotateAngle = (random.nextDouble() - 0.5) * 0.5;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 35),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_ctrl);

    _translateY = Tween<double>(
      begin: 0,
      end: -160,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _rotate = Tween<double>(
      begin: 0,
      end: rotateAngle,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward().then((_) => widget.onComplete());
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
        return Positioned(
          left: widget.position.dx - 36,
          top: widget.position.dy - 36 + _translateY.value,
          child: Transform.rotate(
            angle: _rotate.value,
            child: Opacity(
              opacity: _opacity.value,
              child: Transform.scale(scale: _scale.value, child: child),
            ),
          ),
        );
      },
      child: Icon(
        Icons.favorite_rounded,
        color: _c.primary,
        size: 72,
        shadows: [
          Shadow(color: _c.primaryGlow, blurRadius: 16),
          Shadow(color: _c.shadow, blurRadius: 8),
        ],
      ),
    );
  }
}
