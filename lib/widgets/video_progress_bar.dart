import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../color/app_colors.dart';

const _c = AppColors.dark;

/// Custom video progress bar with:
/// - Played color #FFFFFF 80%
/// - Expands height when dragging
/// - Capsule thumb indicator when dragging
/// - Timestamp display above bar when dragging (00:05/00:45)
class VideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final ValueChanged<bool>? onDraggingChanged;

  const VideoProgressBar({
    super.key,
    required this.controller,
    this.onDraggingChanged,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  bool _dragging = false;
  double _dragFraction = 0.0;

  VideoPlayerController get _ctrl => widget.controller;

  double get _fraction {
    if (_dragging) return _dragFraction;
    final duration = _ctrl.value.duration;
    final position = _ctrl.value.position;
    if (duration.inMilliseconds == 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get _currentPosition {
    if (_dragging) {
      final total = _ctrl.value.duration;
      return Duration(
        milliseconds: (_dragFraction * total.inMilliseconds).round(),
      );
    }
    return _ctrl.value.position;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onDragStart(DragStartDetails details, double barWidth) {
    setState(() {
      _dragging = true;
      _dragFraction = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    });
    widget.onDraggingChanged?.call(true);
  }

  void _onDragUpdate(DragUpdateDetails details, double barWidth) {
    setState(() {
      _dragFraction = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd() {
    final total = _ctrl.value.duration;
    final target = Duration(
      milliseconds: (_dragFraction * total.inMilliseconds).round(),
    );
    _ctrl.seekTo(target);
    setState(() => _dragging = false);
    widget.onDraggingChanged?.call(false);
  }

  void _onTap(TapUpDetails details, double barWidth) {
    final fraction = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    final total = _ctrl.value.duration;
    _ctrl.seekTo(
      Duration(milliseconds: (fraction * total.inMilliseconds).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final fraction = _fraction;
            final barHeight = _dragging ? 6.0 : 3.0;
            final thumbSize = _dragging ? 14.0 : 0.0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timestamp (only visible when dragging)
                AnimatedOpacity(
                  opacity: _dragging ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: TextStyle(
                            color: _c.onSurface,
                            fontSize: 34,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '/${_formatDuration(_ctrl.value.duration)}',
                          style: TextStyle(
                            color: _c.onSurfaceQuaternary,
                            fontSize: 34,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Progress bar + thumb
                GestureDetector(
                  onHorizontalDragStart: (d) => _onDragStart(d, barWidth),
                  onHorizontalDragUpdate: (d) => _onDragUpdate(d, barWidth),
                  onHorizontalDragEnd: (_) => _onDragEnd(),
                  onTapUp: (d) => _onTap(d, barWidth),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    height: 28, // touch target
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Background track
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: _c.shimmer,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                        ),
                        // Played track
                        AnimatedContainer(
                          duration: _dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          height: barHeight,
                          width: fraction * barWidth,
                          decoration: BoxDecoration(
                            color: _c.progressPlayed,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                        ),
                        // Capsule thumb
                        AnimatedPositioned(
                          duration: _dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          left: (fraction * barWidth) - thumbSize / 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: _c.textPrimary,
                              borderRadius: BorderRadius.circular(
                                thumbSize / 2,
                              ),
                              boxShadow: _dragging
                                  ? [
                                      BoxShadow(
                                        color: _c.shadow,
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
