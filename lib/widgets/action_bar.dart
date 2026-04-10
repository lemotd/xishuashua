import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';
import 'comment_sheet.dart';
import 'spring_bottom_sheet.dart';

const _c = AppColors.dark;

class ActionBar extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback? onLikeTriggered;

  const ActionBar({super.key, required this.asset, this.onLikeTriggered});

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
    await showSpringBottomSheet(
      context: context,
      builder: (_) => CommentSheet(assetId: _assetId),
    );
    _commentOpen = false;
    if (mounted) {
      setState(
        () => _commentCount = InteractionService.getCommentCount(_assetId),
      );
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
                  child: Icon(
                    _liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    key: ValueKey(_liked),
                    color: _liked ? _c.primary : _c.icon,
                    size: 34,
                    shadows: _liked
                        ? [Shadow(color: _c.primaryGlow, blurRadius: 12)]
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_likeCount',
                  style: TextStyle(
                    color: _liked ? _c.primary : _c.iconInactive,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
              Icon(
                Icons.chat_bubble_rounded,
                color: _c.icon,
                size: 30,
                shadows: [Shadow(color: _c.shadow, blurRadius: 8)],
              ),
              const SizedBox(height: 2),
              Text(
                '$_commentCount',
                style: TextStyle(
                  color: _c.iconInactive,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
              Icon(
                Icons.near_me_rounded,
                color: _c.icon,
                size: 30,
                shadows: [Shadow(color: _c.shadow, blurRadius: 8)],
              ),
              const SizedBox(height: 2),
              Text(
                '$_shareCount',
                style: TextStyle(
                  color: _c.iconInactive,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
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
