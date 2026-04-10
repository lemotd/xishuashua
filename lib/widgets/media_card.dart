import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../color/app_colors.dart';
import 'video_progress_bar.dart';

const _c = AppColors.dark;

class MediaCard extends StatefulWidget {
  final AssetEntity asset;
  final bool isActive;
  final ValueChanged<bool>? onSpeedChanged;
  final ValueChanged<MediaCardState>? onStateCreated;

  const MediaCard({
    super.key,
    required this.asset,
    required this.isActive,
    this.onSpeedChanged,
    this.onStateCreated,
  });

  @override
  State<MediaCard> createState() => MediaCardState();
}

class MediaCardState extends State<MediaCard>
    with SingleTickerProviderStateMixin {
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;
  bool _isPlaying = false;
  bool _hasStartedPlaying = false;
  bool _showPlayButton = false;
  bool _scrubbing = false;
  bool _speedUp = false;
  Uint8List? _thumbnail;
  late AnimationController _speedIconCtrl;

  // Live Photo state
  bool get _isLivePhoto => widget.asset.isLivePhoto;
  VideoPlayerController? _liveVideoController;
  bool _liveVideoInitialized = false;
  bool _liveVideoPlaying = false;
  bool _liveVideoFinished = false;

  bool get isVideo => widget.asset.type == AssetType.video;

  bool get _isVideo => isVideo;

  /// Expose the best available image bytes for the dislike card thumbnail.
  Uint8List? get snapshotBytes => _imageBytes ?? _thumbnail;

  @override
  void initState() {
    super.initState();
    _speedIconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    widget.onStateCreated?.call(this);
    _loadThumbnail();
    if (_isVideo) {
      _initVideo();
    } else {
      _loadImage();
      if (_isLivePhoto) {
        _initLiveVideo();
      }
    }
  }

  Future<void> _loadThumbnail() async {
    final thumb = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(600, 600),
    );
    if (mounted && thumb != null) {
      setState(() => _thumbnail = thumb);
    }
  }

  @override
  void didUpdateWidget(MediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Asset changed — reload everything from scratch
    if (widget.asset.id != oldWidget.asset.id) {
      _disposeControllers();
      _imageBytes = null;
      _thumbnail = null;
      _videoInitialized = false;
      _videoError = false;
      _isPlaying = false;
      _hasStartedPlaying = false;
      _showPlayButton = false;
      _scrubbing = false;
      _speedUp = false;
      _liveVideoInitialized = false;
      _liveVideoPlaying = false;
      _liveVideoFinished = false;

      _loadThumbnail();
      if (_isVideo) {
        _initVideo();
      } else {
        _loadImage();
        if (_isLivePhoto) {
          _initLiveVideo();
        }
      }
      return;
    }

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        widget.onStateCreated?.call(this);
      }
      if (_isVideo && _videoController != null && _videoInitialized) {
        if (widget.isActive) {
          _videoController!.play();
          if (mounted)
            setState(() {
              _isPlaying = true;
              _hasStartedPlaying = true;
            });
        } else {
          _videoController!.pause();
          _videoController!.seekTo(Duration.zero);
          stopSpeedUp();
          if (mounted)
            setState(() {
              _isPlaying = false;
              _hasStartedPlaying = false;
            });
        }
      }
      // Live Photo: auto-play once when becoming active, reset when leaving
      if (_isLivePhoto &&
          _liveVideoController != null &&
          _liveVideoInitialized) {
        if (widget.isActive) {
          _playLiveVideoOnce();
        } else {
          _resetLiveVideo();
        }
      }
    }
  }

  /// Dispose video controllers without disposing the animation controller.
  void _disposeControllers() {
    _liveVideoController?.removeListener(_onLiveVideoUpdate);
    _liveVideoController?.dispose();
    _liveVideoController = null;
    _videoController?.dispose();
    _videoController = null;
  }

  Future<void> _loadImage() async {
    final bytes = await widget.asset.originBytes;
    if (mounted && bytes != null) {
      setState(() => _imageBytes = bytes);
    }
  }

  /// Initialize the video component of a Live Photo.
  Future<void> _initLiveVideo() async {
    try {
      final File? videoFile = await widget.asset.fileWithSubtype;
      if (videoFile == null || !mounted) return;

      final controller = VideoPlayerController.file(videoFile);
      _liveVideoController = controller;

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.setLooping(false);
      setState(() => _liveVideoInitialized = true);

      // Auto-play once if currently active
      if (widget.isActive) {
        _playLiveVideoOnce();
      }
    } catch (_) {
      // Silently fail — just show the still image
    }
  }

  /// Play the Live Photo video once, then stop.
  void _playLiveVideoOnce() {
    if (_liveVideoController == null || !_liveVideoInitialized) return;
    if (_liveVideoFinished) return; // already played once for this view

    _liveVideoController!.seekTo(Duration.zero);
    _liveVideoController!.play();
    setState(() {
      _liveVideoPlaying = true;
      _liveVideoFinished = false;
    });

    _liveVideoController!.addListener(_onLiveVideoUpdate);
  }

  void _onLiveVideoUpdate() {
    final ctrl = _liveVideoController;
    if (ctrl == null) return;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    // Check if playback reached the end
    if (pos >= dur && dur > Duration.zero) {
      ctrl.removeListener(_onLiveVideoUpdate);
      ctrl.pause();
      if (mounted) {
        setState(() {
          _liveVideoPlaying = false;
          _liveVideoFinished = true;
        });
      }
    }
  }

  /// Reset Live Photo state so it can play again next time it becomes active.
  void _resetLiveVideo() {
    _liveVideoController?.removeListener(_onLiveVideoUpdate);
    _liveVideoController?.pause();
    _liveVideoController?.seekTo(Duration.zero);
    if (mounted) {
      setState(() {
        _liveVideoPlaying = false;
        _liveVideoFinished = false;
      });
    }
  }

  Future<void> _initVideo() async {
    try {
      final File? file = await widget.asset.file;
      if (file == null || !mounted) return;

      final controller = VideoPlayerController.file(file);
      _videoController = controller;

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      controller.setLooping(true);
      setState(() => _videoInitialized = true);

      // Delay play to next frame so the thumbnail covers the raw first frame
      if (widget.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _videoController == null) return;
          _videoController!.play();
          setState(() {
            _isPlaying = true;
            _hasStartedPlaying = true;
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _videoError = true);
      }
    }
  }

  void _toggleVideoPlayback() {
    if (!_isVideo || _videoController == null || !_videoInitialized) return;
    if (_speedUp) return; // don't toggle during speed-up
    if (_isPlaying) {
      _videoController!.pause();
      setState(() {
        _isPlaying = false;
        _showPlayButton = true;
      });
    } else {
      _videoController!.play();
      setState(() {
        _isPlaying = true;
        _hasStartedPlaying = true;
        _showPlayButton = true;
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showPlayButton = false);
      });
    }
  }

  void startSpeedUp() {
    if (!_isVideo || _videoController == null || !_videoInitialized) return;
    if (!_isPlaying) return;
    HapticFeedback.mediumImpact();
    _videoController!.setPlaybackSpeed(2.0);
    _speedIconCtrl.repeat();
    setState(() => _speedUp = true);
    widget.onSpeedChanged?.call(true);
  }

  void stopSpeedUp() {
    if (!_speedUp) return;
    _videoController?.setPlaybackSpeed(1.0);
    _speedIconCtrl.stop();
    _speedIconCtrl.reset();
    setState(() => _speedUp = false);
    widget.onSpeedChanged?.call(false);
  }

  @override
  void dispose() {
    _speedIconCtrl.dispose();
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isVideo ? _toggleVideoPlayback : null,
      child: Container(
        color: _c.background,
        child: _isVideo ? _buildVideoView() : _buildImageView(),
      ),
    );
  }

  Widget _buildImageView() {
    final bytes = _imageBytes ?? _thumbnail;
    if (bytes == null) {
      return Center(child: CircularProgressIndicator(color: _c.primary));
    }

    // Live Photo: overlay video on top of still image
    if (_isLivePhoto && _liveVideoInitialized && _liveVideoController != null) {
      final controller = _liveVideoController!;
      final aspectRatio = controller.value.aspectRatio;
      final safeAspectRatio = (aspectRatio.isFinite && aspectRatio > 0)
          ? aspectRatio
          : 16 / 9;

      return Stack(
        fit: StackFit.expand,
        children: [
          // Still image underneath
          _imageWidget(bytes),
          // Video layer — visible while playing
          if (_liveVideoPlaying)
            Center(
              child: AspectRatio(
                aspectRatio: safeAspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          // LIVE badge (top-left)
          Positioned(
            top: 100,
            left: 16,
            child: AnimatedOpacity(
              opacity: _liveVideoPlaying ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _c.overlay,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _liveVideoPlaying
                          ? Icons.motion_photos_on_rounded
                          : Icons.motion_photos_pause_rounded,
                      color: _c.icon,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: _c.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return _imageWidget(bytes);
  }

  Widget _imageWidget(Uint8List bytes) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_rounded, color: _c.textHint, size: 64),
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    // Error state
    if (_videoError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: _c.textHint, size: 48),
            const SizedBox(height: 8),
            Text('视频加载失败', style: TextStyle(color: _c.textSecondary)),
          ],
        ),
      );
    }

    // Loading state
    if (!_videoInitialized || _videoController == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_thumbnail != null)
            Center(child: Image.memory(_thumbnail!, fit: BoxFit.contain)),
          Center(child: CircularProgressIndicator(color: _c.primary)),
        ],
      );
    }

    final controller = _videoController!;
    final aspectRatio = controller.value.aspectRatio;
    // Guard against invalid aspect ratio
    final safeAspectRatio = (aspectRatio.isFinite && aspectRatio > 0)
        ? aspectRatio
        : 16 / 9;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: safeAspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        // Keep thumbnail on top until video has started playing to prevent flash
        if (!_hasStartedPlaying && _thumbnail != null)
          Center(child: Image.memory(_thumbnail!, fit: BoxFit.contain)),
        if (_showPlayButton || !_isPlaying)
          Center(
            child: AnimatedOpacity(
              opacity: (_showPlayButton || !_isPlaying) ? 0.7 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _c.overlay,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.play_arrow : Icons.pause,
                  color: _c.textPrimary,
                  size: 48,
                ),
              ),
            ),
          ),
        // Bottom gradient overlay — extends higher when scrubbing to cover timestamp
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _scrubbing ? 260 : 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [_c.gradientStart, _c.gradientEnd],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: 16,
          right: 16,
          child: VideoProgressBar(
            controller: controller,
            onDraggingChanged: (dragging) {
              setState(() => _scrubbing = dragging);
            },
          ),
        ),
      ],
    );
  }
}
