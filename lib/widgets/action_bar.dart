import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';
import 'voice_input_sheet.dart';

const _c = AppColors.dark;

class ActionBar extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback? onLikeTriggered;

  /// Callback when a comment is successfully posted, with the comment text.
  final ValueChanged<String>? onCommentPosted;

  const ActionBar({
    super.key,
    required this.asset,
    this.onLikeTriggered,
    this.onCommentPosted,
  });

  @override
  State<ActionBar> createState() => ActionBarState();
}

class ActionBarState extends State<ActionBar>
    with SingleTickerProviderStateMixin {
  late int _likeCount;
  late int _commentCount;
  late int _shareCount;
  late AnimationController _likeAnimCtrl;
  late Animation<double> _likeScale;

  String get _assetId => widget.asset.id;

  @override
  void initState() {
    super.initState();
    _likeAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _likeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _likeAnimCtrl, curve: Curves.easeOut));
    _refresh();
  }

  @override
  void didUpdateWidget(ActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _refresh();
  }

  void _refresh() {
    _likeCount = InteractionService.getLikeCount(_assetId);
    _commentCount = InteractionService.getCommentCount(_assetId);
    _shareCount = InteractionService.getShareCount(_assetId);
  }

  bool get _liked => _likeCount > 0;

  void triggerLike() {
    InteractionService.addLike(_assetId);
    setState(() => _likeCount = InteractionService.getLikeCount(_assetId));
    _playLikeAnim();
    widget.onLikeTriggered?.call();
  }

  void _onLikeTap() {
    InteractionService.addLike(_assetId);
    setState(() => _likeCount = InteractionService.getLikeCount(_assetId));
    _playLikeAnim();
    widget.onLikeTriggered?.call();
  }

  void _onLikeLongPress() {
    if (_likeCount <= 0) return;
    HapticFeedback.mediumImpact();
    InteractionService.removeLike(_assetId);
    setState(() => _likeCount = InteractionService.getLikeCount(_assetId));
  }

  void _playLikeAnim() {
    HapticFeedback.lightImpact();
    _likeAnimCtrl.forward(from: 0);
  }

  bool _commentOpen = false;

  void _onComment() async {
    if (_commentOpen) return;
    _commentOpen = true;
    String? postedText;
    await VoiceInputSheet.show(
      context,
      typingHint: '写评论...',
      listeningHint: '说点什么...',
      onSubmit: (text) {
        InteractionService.addComment(_assetId, text);
        postedText = text;
      },
    );
    _commentOpen = false;
    if (mounted) {
      setState(
        () => _commentCount = InteractionService.getCommentCount(_assetId),
      );
      if (postedText != null) {
        widget.onCommentPosted?.call(postedText!);
      }
    }
  }

  void _onShare() async {
    final File? file = await widget.asset.file;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
    InteractionService.incrementShare(_assetId);
    setState(() => _shareCount = InteractionService.getShareCount(_assetId));
  }

  @override
  void dispose() {
    _likeAnimCtrl.dispose();
    super.dispose();
  }

  static const _iconShadows = [Shadow(color: Color(0x40000000), blurRadius: 4)];

  Widget _svgWithShadow(
    String path, {
    required double size,
    ColorFilter? colorFilter,
    Key? key,
  }) {
    return ImageFiltered(
      imageFilter: ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        inner: ColorFilter.mode(const Color(0x99000000), BlendMode.srcATop),
      ),
      enabled: false,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Shadow layer
          Positioned(
            top: 1,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: SvgPicture.asset(
                path,
                key: key != null ? ValueKey('${key}_shadow') : null,
                width: size,
                height: size,
                colorFilter: const ColorFilter.mode(
                  Color(0x33000000),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          // Foreground layer
          SvgPicture.asset(
            path,
            key: key,
            width: size,
            height: size,
            colorFilter: colorFilter,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _likeScale,
          builder: (context, child) =>
              Transform.scale(scale: _likeScale.value, child: child),
          child: _PressableButton(
            onTap: _onLikeTap,
            onLongPress: _onLikeLongPress,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: _svgWithShadow(
                    'images/like.svg',
                    size: 36,
                    colorFilter: ColorFilter.mode(
                      _liked ? _c.primary : _c.icon,
                      BlendMode.srcIn,
                    ),
                    key: ValueKey(_liked),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_likeCount',
                  style: TextStyle(
                    color: _liked ? _c.primary : _c.iconInactive,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    shadows: _iconShadows,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _PressableButton(
          onTap: _onComment,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _svgWithShadow(
                'images/comment.svg',
                size: 36,
                colorFilter: ColorFilter.mode(_c.icon, BlendMode.srcIn),
              ),
              const SizedBox(height: 2),
              Text(
                '$_commentCount',
                style: TextStyle(
                  color: _c.iconInactive,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  shadows: _iconShadows,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PressableButton(
          onTap: _onShare,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _svgWithShadow(
                'images/forward.svg',
                size: 36,
                colorFilter: ColorFilter.mode(_c.icon, BlendMode.srcIn),
              ),
              const SizedBox(height: 2),
              Text(
                '$_shareCount',
                style: TextStyle(
                  color: _c.iconInactive,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  shadows: _iconShadows,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PressableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PressableButton({
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _delayedReverse() {
    // Ensure the shrink animation is visible even on quick taps
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _delayedReverse();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: _delayedReverse,
      onLongPress: widget.onLongPress != null
          ? () {
              _ctrl.reverse();
              widget.onLongPress!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}
