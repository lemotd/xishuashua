import 'dart:async';
import 'dart:typed_data';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';

const _c = AppColors.dark;

/// Auto-playing carousel for grouped similar photos.
/// 3s per slide, loops infinitely, progress bar fills up per slide.
/// Manual swipe cancels auto-play permanently for this card.
class CarouselCard extends StatefulWidget {
  final List<AssetEntity> assets;
  final ValueChanged<Uint8List?>? onSnapshotReady;
  final ValueChanged<AssetEntity>? onSlideChanged;
  final int initialPage;

  const CarouselCard({
    super.key,
    required this.assets,
    this.onSnapshotReady,
    this.onSlideChanged,
    this.initialPage = 0,
  });

  @override
  State<CarouselCard> createState() => CarouselCardState();
}

class CarouselCardState extends State<CarouselCard>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  int _current = 0;
  bool _autoPlay = true;
  bool _userDragging = false;
  Timer? _autoTimer;
  Uint8List? _currentThumbnail;

  // Progress animation: fills 0→1 over 3 seconds per slide
  late AnimationController _progressCtrl;

  static const _slideDuration = Duration(seconds: 3);

  Uint8List? get snapshotBytes => _currentThumbnail;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage.clamp(0, widget.assets.length - 1);
    _pageCtrl = PageController(initialPage: _current);
    _progressCtrl = AnimationController(vsync: this, duration: _slideDuration);
    _startAutoPlay();
    _loadCurrentThumbnail();
    // Report initial slide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSlideChanged?.call(widget.assets[_current]);
    });
  }

  void _startAutoPlay() {
    if (!_autoPlay) return;
    _progressCtrl.forward(from: 0);
    _autoTimer?.cancel();
    _autoTimer = Timer(_slideDuration, _advancePage);
  }

  void _advancePage() {
    if (!_autoPlay || !mounted) return;
    final next = (_current + 1) % widget.assets.length;
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    // onPageChanged will call _startAutoPlay again
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    if (_autoPlay && !_userDragging) {
      _startAutoPlay();
    }
    _loadCurrentThumbnail();
    widget.onSlideChanged?.call(widget.assets[index]);
  }

  Future<void> _loadCurrentThumbnail() async {
    final asset = widget.assets[_current];
    final bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(600, 600),
    );
    if (mounted && bytes != null) {
      _currentThumbnail = bytes;
      widget.onSnapshotReady?.call(bytes);
    }
  }

  void _onUserDragStart() {
    _userDragging = true;
    // User touched — cancel auto-play permanently
    _autoPlay = false;
    _autoTimer?.cancel();
    _progressCtrl.stop();
  }

  void _onUserDragEnd() {
    _userDragging = false;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _progressCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.assets.length;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Swipeable pages with drag detection
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _onUserDragStart();
            } else if (notification is ScrollEndNotification) {
              _onUserDragEnd();
            }
            return false;
          },
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: count,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              return _CarouselImage(asset: widget.assets[index]);
            },
          ),
        ),
        // Group badge (top-left)
        Positioned(
          top: 100,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _c.overlay,
              borderRadius: SmoothBorderRadius(
                cornerRadius: 12,
                cornerSmoothing: 0.6,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.burst_mode_rounded, color: _c.icon, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_current + 1}/$count',
                  style: TextStyle(
                    color: _c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom progress bar
        Positioned(
          bottom: 48,
          left: 16,
          right: 16,
          child: _AnimatedProgressBar(
            total: count,
            current: _current,
            animation: _progressCtrl,
            autoPlay: _autoPlay,
          ),
        ),
      ],
    );
  }
}

/// A single image in the carousel.
class _CarouselImage extends StatefulWidget {
  final AssetEntity asset;

  const _CarouselImage({required this.asset});

  @override
  State<_CarouselImage> createState() => _CarouselImageState();
}

class _CarouselImageState extends State<_CarouselImage> {
  Uint8List? _fullBytes;

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

  Future<void> _loadFull() async {
    final bytes = await widget.asset.originBytes;
    if (mounted && bytes != null) {
      setState(() => _fullBytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fullBytes != null) {
      return InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            _fullBytes!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: widget.asset.thumbnailDataWithSize(const ThumbnailSize(600, 600)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          );
        }
        return Center(child: CircularProgressIndicator(color: _c.primary));
      },
    );
  }
}

/// Segmented progress bar with animated fill on the current segment.
class _AnimatedProgressBar extends StatelessWidget {
  final int total;
  final int current;
  final AnimationController animation;
  final bool autoPlay;

  const _AnimatedProgressBar({
    required this.total,
    required this.current,
    required this.animation,
    required this.autoPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final isPast = i < current;
        final isCurrent = i == current;

        return Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 1.5,
                cornerSmoothing: 0.6,
              ),
              color: isPast
                  ? _c.textPrimary
                  : _c.textPrimary.withValues(alpha: 0.3),
            ),
            child: isCurrent
                ? AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: autoPlay ? animation.value : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: SmoothBorderRadius(
                              cornerRadius: 1.5,
                              cornerSmoothing: 0.6,
                            ),
                            color: _c.textPrimary,
                          ),
                        ),
                      );
                    },
                  )
                : null,
          ),
        );
      }),
    );
  }
}
