import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'black_hole_overlay.dart';

typedef OnDislikeCallback = void Function();

/// Wraps the feed content and directly transforms it for the dislike gesture.
/// The widget tree is kept 100% stable — same number and type of children
/// at all times — so the child (PageView) is never remounted.
class DislikeGestureWrapper extends StatefulWidget {
  final Widget child;
  final OnDislikeCallback onDislike;
  final ValueChanged<bool>? onActiveChanged;

  const DislikeGestureWrapper({
    super.key,
    required this.child,
    required this.onDislike,
    this.onActiveChanged,
  });

  @override
  State<DislikeGestureWrapper> createState() => DislikeGestureWrapperState();
}

class DislikeGestureWrapperState extends State<DislikeGestureWrapper>
    with TickerProviderStateMixin {
  bool _active = false;
  bool _hoveringHole = false;
  bool _suckingIn = false;

  Offset _dragOffset = Offset.zero;
  Offset _longPressOrigin = Offset.zero;

  late AnimationController _shrinkCtrl;
  late AnimationController _overlayCtrl;
  late AnimationController _suckCtrl;
  late AnimationController _snapBackCtrl;

  Offset _snapStart = Offset.zero;

  static const _cardScale = 0.55;
  static const _cardRadius = 20.0;

  bool get active => _active || _shrinkCtrl.value > 0;

  double get _holeCenterY {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return size.height - bottomPadding - 70;
  }

  @override
  void initState() {
    super.initState();
    _shrinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 320),
    );
    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _suckCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _snapBackCtrl.addListener(_onSnapBack);
    _suckCtrl.addStatusListener(_onSuckComplete);
  }

  @override
  void dispose() {
    _shrinkCtrl.dispose();
    _overlayCtrl.dispose();
    _suckCtrl.dispose();
    _snapBackCtrl.dispose();
    super.dispose();
  }

  // ── Public API ──

  void onLongPressStart(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    setState(() {
      _active = true;
      _longPressOrigin = details.globalPosition;
      _dragOffset = Offset.zero;
    });
    _shrinkCtrl.forward();
    _overlayCtrl.forward();
    widget.onActiveChanged?.call(true);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_active || _suckingIn) return;
    setState(() {
      _dragOffset = details.globalPosition - _longPressOrigin;
    });
    _checkHover();
  }

  void onLongPressEnd(LongPressEndDetails details) {
    if (!_active || _suckingIn) return;
    if (_hoveringHole) {
      _startSuckIn();
    } else {
      _startSnapBack();
    }
  }

  void _checkHover() {
    final cardY = _longPressOrigin.dy + _dragOffset.dy;
    final hovering = cardY > _holeCenterY - 40;
    if (hovering != _hoveringHole) {
      if (hovering) HapticFeedback.selectionClick();
      setState(() => _hoveringHole = hovering);
    }
  }

  void _startSuckIn() {
    HapticFeedback.heavyImpact();
    setState(() {
      _suckingIn = true;
      _snapStart = _dragOffset;
    });
    _suckCtrl.forward(from: 0);
  }

  void _onSuckComplete(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _shrinkCtrl.value = 0;
    _overlayCtrl.value = 0;
    _suckCtrl.value = 0;
    setState(() {
      _active = false;
      _hoveringHole = false;
      _suckingIn = false;
      _dragOffset = Offset.zero;
    });
    widget.onActiveChanged?.call(false);
    widget.onDislike();
  }

  void _startSnapBack() {
    _snapStart = _dragOffset;
    _shrinkCtrl.reverse().then((_) {
      if (mounted) widget.onActiveChanged?.call(false);
    });
    _overlayCtrl.reverse();
    _snapBackCtrl.forward(from: 0);
  }

  void _onSnapBack() {
    if (!_active) return;
    final t = Curves.easeOutCubic.transform(_snapBackCtrl.value);
    setState(() {
      _dragOffset = Offset.lerp(_snapStart, Offset.zero, t)!;
    });
    if (_snapBackCtrl.isCompleted) {
      setState(() {
        _active = false;
        _hoveringHole = false;
        _suckingIn = false;
        _dragOffset = Offset.zero;
      });
    }
  }

  // ── Build ──
  // Children count is ALWAYS 3: background, content, overlay.
  // No conditionals that add/remove children.

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: Listenable.merge([_shrinkCtrl, _suckCtrl, _overlayCtrl]),
      builder: (context, child) {
        final shrinkT = Curves.easeOutCubic.transform(_shrinkCtrl.value);

        double scale;
        double opacity = 1.0;
        Offset offset;

        if (_suckingIn) {
          final suckT = Curves.easeInCubic.transform(_suckCtrl.value);
          scale = _cardScale * (1 - suckT);
          opacity = 1 - suckT;
          // Card center moves from current drag position to hole
          final curCenter = _longPressOrigin + _snapStart;
          final holeCenter = Offset(size.width / 2, _holeCenterY);
          final center = Offset.lerp(curCenter, holeCenter, suckT)!;
          offset = center - Offset(size.width / 2, size.height / 2);
        } else {
          scale = 1.0 - (1.0 - _cardScale) * shrinkT;
          // Offset: press point pulls the content toward it as it shrinks
          final pressOffset =
              _longPressOrigin - Offset(size.width / 2, size.height / 2);
          offset = (pressOffset + _dragOffset) * shrinkT;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // [0] Black background — visible when content is shrunk
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: shrinkT),
                ),
              ),
            ),
            // [1] Content — always here, transformed in place
            Positioned.fill(
              child: Transform.translate(
                offset: offset,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: ClipSmoothRect(
                      radius: SmoothBorderRadius(
                        cornerRadius: _cardRadius * shrinkT,
                        cornerSmoothing: 0.6,
                      ),
                      child: child!,
                    ),
                  ),
                ),
              ),
            ),
            // [2] Black hole overlay — always present, controlled by opacity
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: _overlayCtrl.value,
                  child: BlackHoleOverlay(
                    isHovering: _hoveringHole,
                    entranceAnimation: CurvedAnimation(
                      parent: _overlayCtrl,
                      curve: Curves.easeOut,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}
