import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../color/app_colors.dart';

const _c = AppColors.dark;

class BlackHoleOverlay extends StatefulWidget {
  final bool isHovering;
  final Animation<double> entranceAnimation;

  const BlackHoleOverlay({
    super.key,
    required this.isHovering,
    required this.entranceAnimation,
  });

  @override
  State<BlackHoleOverlay> createState() => _BlackHoleOverlayState();
}

class _BlackHoleOverlayState extends State<BlackHoleOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    // Continuous 0→1 loop for flowing effects
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const arcHeight = 140.0;
    final baseHeight = arcHeight + bottomPadding;
    final hoverExtra = widget.isHovering ? 18.0 : 0.0;

    return AnimatedBuilder(
      animation: widget.entranceAnimation,
      builder: (context, child) {
        final t = widget.entranceAnimation.value;
        return Transform.translate(
          offset: Offset(0, baseHeight * (1 - t)),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: screenWidth,
        height: baseHeight + hoverExtra,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _PocketPainter(
                      isHovering: widget.isHovering,
                      time: _animCtrl.value,
                      bottomPadding: bottomPadding,
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 56 + hoverExtra * 0.4,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '不喜欢 拖到这',
                  style: TextStyle(
                    color: widget.isHovering
                        ? _c.primary
                        : _c.onSurfaceTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PocketPainter extends CustomPainter {
  final bool isHovering;
  final double time; // 0→1 continuous loop
  final double bottomPadding;

  _PocketPainter({
    required this.isHovering,
    required this.time,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arcDepth = 72.0;
    final baseColor = isHovering ? _c.primary : Colors.white;

    // ── 1. Dark pocket fill ──
    final pocketPath = _arcPath(w, h, arcDepth);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isHovering
            ? [
                _c.primary.withValues(alpha: 0.25),
                _c.primary.withValues(alpha: 0.6),
                _c.primary.withValues(alpha: 0.85),
              ]
            : [
                Colors.black.withValues(alpha: 0.4),
                Colors.black.withValues(alpha: 0.8),
                Colors.black.withValues(alpha: 0.95),
              ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(pocketPath, fillPaint);

    // ── 2. Flowing gradient edge ──
    _drawFlowingEdge(canvas, w, h, arcDepth, baseColor);
  }

  Path _arcPath(double w, double h, double arcDepth) {
    return Path()
      ..moveTo(0, h)
      ..lineTo(0, arcDepth + bottomPadding)
      ..quadraticBezierTo(w / 2, 0, w, arcDepth + bottomPadding)
      ..lineTo(w, h)
      ..close();
  }

  /// Flowing gradient highlight that sweeps along the arc edge.
  void _drawFlowingEdge(
    Canvas canvas,
    double w,
    double h,
    double arcDepth,
    Color baseColor,
  ) {
    final edgePath = Path()
      ..moveTo(0, arcDepth + bottomPadding)
      ..quadraticBezierTo(w / 2, 0, w, arcDepth + bottomPadding);

    // Soft glow underneath
    canvas.drawPath(
      edgePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..color = baseColor.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Flowing bright spot — a sweep gradient that rotates with time
    // We sample points along the arc and draw a brighter segment
    final pathMetrics = edgePath.computeMetrics().first;
    final totalLen = pathMetrics.length;

    // The bright spot center moves along the path
    final spotCenter = (time * totalLen) % totalLen;
    final spotRadius = totalLen * 0.18; // width of the bright region

    for (double d = 0; d < totalLen; d += 2.0) {
      final tangent = pathMetrics.getTangentForOffset(d);
      if (tangent == null) continue;

      // Distance from the bright spot center (wrapping around)
      var dist = (d - spotCenter).abs();
      if (dist > totalLen / 2) dist = totalLen - dist;

      final brightness = math.max(0.0, 1.0 - dist / spotRadius);
      if (brightness <= 0) continue;

      final alpha = isHovering
          ? 0.3 + brightness * 0.7
          : 0.1 + brightness * 0.4;

      canvas.drawCircle(
        tangent.position,
        isHovering ? 2.5 : 1.8,
        Paint()
          ..color = baseColor.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            3.0 + brightness * 4,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_PocketPainter old) => true;
}
