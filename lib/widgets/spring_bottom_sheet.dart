import 'package:flutter/material.dart';
import 'sheet_spring_curve.dart';

/// Shows a bottom sheet with spring physics animation and drag-to-dismiss.
Future<T?> showSpringBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push<T>(_SpringSheetRoute<T>(builder: builder));
}

/// Provides the real keyboard height to descendants even when the
/// parent strips viewInsets from MediaQuery.
class KeyboardInset extends InheritedWidget {
  final double bottom;

  const KeyboardInset({super.key, required this.bottom, required super.child});

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<KeyboardInset>()
            ?.bottom ??
        0;
  }

  @override
  bool updateShouldNotify(KeyboardInset oldWidget) =>
      bottom != oldWidget.bottom;
}

class _SpringSheetRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;

  _SpringSheetRoute({required this.builder});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 545);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 420);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _DraggableSheet(route: this, child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isReversing = animation.status == AnimationStatus.reverse;
    final animValue = animation.value;

    final slideY = isReversing
        ? 1.0 - Curves.easeInOutCubic.transform(animValue)
        : 1.0 - SheetSpringCurve.instance.transform(animValue);

    // Capture the real keyboard height before stripping viewInsets.
    final realKeyboard = MediaQuery.of(context).viewInsets.bottom;

    // Strip viewInsets so Align doesn't push the sheet up when the
    // keyboard opens. Pass the real value via KeyboardInset so the
    // sheet's input bar can position itself correctly.
    final strippedMq = MediaQuery.of(
      context,
    ).copyWith(viewInsets: EdgeInsets.zero);

    return MediaQuery(
      data: strippedMq,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: ColoredBox(
                color: Color.lerp(
                  Colors.transparent,
                  const Color(0x66000000),
                  animation.value,
                )!,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionalTranslation(
              translation: Offset(0, slideY),
              child: KeyboardInset(bottom: realKeyboard, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps the sheet content to support drag-to-dismiss.
class _DraggableSheet extends StatefulWidget {
  final PopupRoute route;
  final Widget child;

  const _DraggableSheet({required this.route, required this.child});

  @override
  State<_DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<_DraggableSheet> {
  double _dragOffset = 0;
  bool _isDragging = false;

  void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragOffset = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: widget.child,
      ),
    );
  }
}
