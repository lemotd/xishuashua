import 'dart:async';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';
import 'collection_detail_page.dart';

const _c = AppColors.dark;

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _c.background,
        body: Column(
          children: [
            // ── Custom header: safe area + nav bar + tabs ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topPadding),
                // Nav bar: 56px
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      GlassCircleButton(
                        child: SvgPicture.asset(
                          'images/back.svg',
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            _c.textPrimary,
                            BlendMode.srcIn,
                          ),
                        ),
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Text(
                        '合集',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: _c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Balance the back button width
                      const SizedBox(width: 52),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // ── Tab bar ──
                _CustomTabBar(controller: _tabController),
              ],
            ),
            // ── Tab content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_DislikedGrid(), _LikedGrid(), _SharedGrid()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glass circle button with highlight effect ──

class GlassCircleButton extends StatelessWidget {
  final Widget? child;
  final VoidCallback onTap;

  const GlassCircleButton({super.key, this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _c.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.6,
            ),
          ),
        ),
        child: child != null ? Center(child: child) : null,
      ),
    );
  }
}

// ── Press-to-shrink feedback wrapper ──

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.92,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  Timer? _releaseDelay;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: widget.scaleDown,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _releaseDelay?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    _releaseDelay?.cancel();
    _ctrl.forward();
  }

  void _onUp(TapUpDetails _) {
    // 80ms minimum hold so quick taps still show the animation
    _releaseDelay?.cancel();
    _releaseDelay = Timer(const Duration(milliseconds: 80), () {
      if (mounted) _ctrl.reverse();
    });
  }

  void _onCancel() {
    _releaseDelay?.cancel();
    _releaseDelay = Timer(const Duration(milliseconds: 80), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onCancel,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Custom tab bar with smooth sliding pill highlight ──

class _CustomTabBar extends StatelessWidget {
  final TabController controller;

  const _CustomTabBar({required this.controller});

  static const _icons = [
    'images/dislike.svg',
    'images/like.svg',
    'images/forward.svg',
  ];
  static const _labels = ['不喜欢', '喜欢', '转发'];

  static const _iconSize = 22.0;
  static const _gap = 8.0;
  static const _tabHeight = 40.0;
  static const _radius = 20.0;

  // Padding-driven sizing
  static const _hPadCollapsed = 16.0; // icon-only horizontal padding
  static const _hPadExpanded = 18.0; // selected horizontal padding
  static const _labelGap = 6.0;
  // Pre-measured label widths (generous to avoid clipping)
  static const _labelWidths = [46.0, 31.0, 31.0];

  // Derived widths from padding + content
  static double _collapsedWidth() => _hPadCollapsed * 2 + _iconSize;

  static double _expandedWidth(int i) =>
      _hPadExpanded * 2 + _iconSize + _labelGap + _labelWidths[i];

  static double _tabWidth(int i, double progress) {
    return _collapsedWidth() +
        (_expandedWidth(i) - _collapsedWidth()) * progress;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) {
        final anim = controller.animation!.value;

        // Per-tab progress & width
        final progresses = <double>[];
        final widths = <double>[];
        for (int i = 0; i < 3; i++) {
          final p = (1.0 - (anim - i).abs()).clamp(0.0, 1.0);
          progresses.add(p);
          widths.add(_tabWidth(i, p));
        }

        // Purple highlight absolute position & size
        final lefts = <double>[];
        double x = 0;
        for (int i = 0; i < 3; i++) {
          lefts.add(x);
          x += widths[i] + (i < 2 ? _gap : 0);
        }
        final floor = anim.floor().clamp(0, 1);
        final ceil = (floor + 1).clamp(0, 2);
        final t = anim - floor;
        final hlLeft = lefts[floor] + (lefts[ceil] - lefts[floor]) * t;
        final hlWidth = widths[floor] + (widths[ceil] - widths[floor]) * t;

        return SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final progress = progresses[i];
                final w = widths[i];
                final purpleOffset = hlLeft - lefts[i];
                final hPad =
                    _hPadCollapsed +
                    (_hPadExpanded - _hPadCollapsed) * progress;

                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? _gap : 0),
                  child: PressableScale(
                    onTap: () => controller.animateTo(i),
                    child: SizedBox(
                      width: w,
                      height: _tabHeight,
                      child: ClipSmoothRect(
                        radius: SmoothBorderRadius(
                          cornerRadius: _radius,
                          cornerSmoothing: 0.6,
                        ),
                        child: Stack(
                          children: [
                            // Unselected bg
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _c.surfaceContainerHigh,
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      width: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Purple highlight — clipped by ClipSmoothRect
                            Positioned(
                              left: purpleOffset,
                              top: 0,
                              child: Container(
                                width: hlWidth,
                                height: _tabHeight,
                                decoration: BoxDecoration(
                                  color: _c.highlightPurple,
                                  borderRadius: SmoothBorderRadius(
                                    cornerRadius: _radius,
                                    cornerSmoothing: 0.6,
                                  ),
                                ),
                              ),
                            ),
                            // Top highlight border on purple
                            Positioned(
                              left: purpleOffset,
                              top: 0,
                              child: Container(
                                width: hlWidth,
                                height: 0.6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: SmoothBorderRadius.only(
                                    topLeft: SmoothRadius(
                                      cornerRadius: _radius,
                                      cornerSmoothing: 0.6,
                                    ),
                                    topRight: SmoothRadius(
                                      cornerRadius: _radius,
                                      cornerSmoothing: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Content with padding
                            Positioned.fill(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: hPad),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SvgPicture.asset(
                                      _icons[i],
                                      width: _iconSize,
                                      height: _iconSize,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    ClipRect(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: progress,
                                        child: Opacity(
                                          opacity: progress,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: _labelGap,
                                            ),
                                            child: Text(
                                              _labels[i],
                                              maxLines: 1,
                                              softWrap: false,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

// ── Grid tabs ──

class _DislikedGrid extends StatefulWidget {
  const _DislikedGrid();
  @override
  State<_DislikedGrid> createState() => _DislikedGridState();
}

class _DislikedGridState extends State<_DislikedGrid>
    with AutomaticKeepAliveClientMixin {
  List<_GridItem> _items = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dislikedIds = InteractionService.getAllDisliked();
    final items = <_GridItem>[];
    for (final id in dislikedIds) {
      final asset = await AssetEntity.fromId(id);
      if (asset != null) {
        final likeCount = InteractionService.getLikeCount(id);
        items.add(_GridItem(asset: asset, count: likeCount));
      }
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _c.primary));
    }
    if (_items.isEmpty) {
      return _buildEmpty('还没有不喜欢的内容');
    }
    return _VideoGrid(items: _items, isLike: true);
  }
}

class _LikedGrid extends StatefulWidget {
  const _LikedGrid();
  @override
  State<_LikedGrid> createState() => _LikedGridState();
}

class _LikedGridState extends State<_LikedGrid>
    with AutomaticKeepAliveClientMixin {
  List<_GridItem> _items = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final likedMap = InteractionService.getAllLiked();
    final items = <_GridItem>[];
    for (final entry in likedMap.entries) {
      final asset = await AssetEntity.fromId(entry.key);
      if (asset != null) {
        items.add(_GridItem(asset: asset, count: entry.value));
      }
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _c.primary));
    }
    if (_items.isEmpty) {
      return _buildEmpty('还没有喜欢的内容');
    }
    return _VideoGrid(items: _items, isLike: true);
  }
}

class _SharedGrid extends StatefulWidget {
  const _SharedGrid();
  @override
  State<_SharedGrid> createState() => _SharedGridState();
}

class _SharedGridState extends State<_SharedGrid>
    with AutomaticKeepAliveClientMixin {
  List<_GridItem> _items = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sharedMap = InteractionService.getAllShared();
    final items = <_GridItem>[];
    for (final entry in sharedMap.entries) {
      final asset = await AssetEntity.fromId(entry.key);
      if (asset != null) {
        items.add(_GridItem(asset: asset, count: entry.value));
      }
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _c.primary));
    }
    if (_items.isEmpty) {
      return _buildEmpty('还没有分享过的内容');
    }
    return _VideoGrid(items: _items, isLike: false);
  }
}

// ── Shared components ──

class _GridItem {
  final AssetEntity asset;
  final int count;
  const _GridItem({required this.asset, required this.count});
}

Widget _buildEmpty(String text) {
  return Center(
    child: Text(text, style: TextStyle(color: _c.textHint, fontSize: 14)),
  );
}

class _VideoGrid extends StatelessWidget {
  final List<_GridItem> items;
  final bool isLike;
  const _VideoGrid({required this.items, required this.isLike});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 3 / 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _GridTile(
          item: items[index],
          isLike: isLike,
          allItems: items,
          index: index,
        );
      },
    );
  }
}

class _GridTile extends StatefulWidget {
  final _GridItem item;
  final bool isLike;
  final List<_GridItem> allItems;
  final int index;
  const _GridTile({
    required this.item,
    required this.isLike,
    required this.allItems,
    required this.index,
  });

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final bytes = await widget.item.asset.thumbnailDataWithSize(
      const ThumbnailSize(300, 400),
    );
    if (mounted && bytes != null) {
      setState(() => _thumb = bytes);
    }
  }

  String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  void _openDetail() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;

    Navigator.push(
      context,
      ZoomPageRoute(
        originRect: rect,
        thumbBytes: _thumb,
        page: CollectionDetailPage(
          assets: widget.allItems.map((e) => e.asset).toList(),
          initialIndex: widget.index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: _openDetail,
      scaleDown: 0.95,
      child: Container(
        color: _c.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumb != null)
              Image.memory(_thumb!, fit: BoxFit.cover)
            else
              Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _c.textHint,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isLike ? Icons.favorite : Icons.reply,
                    color: Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _formatCount(widget.item.count),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS Photos-style zoom transition.
/// The thumbnail expands from the grid tile to fullscreen without any fade.
/// The page content sits behind the thumbnail and is revealed only once
/// the animation completes (t == 1.0). On pop the reverse happens.
class ZoomPageRoute extends PageRouteBuilder {
  final Rect originRect;
  final Uint8List? thumbBytes;

  ZoomPageRoute({
    required this.originRect,
    required this.thumbBytes,
    required Widget page,
  }) : super(
         opaque: false,
         barrierColor: Colors.transparent,
         transitionDuration: const Duration(milliseconds: 350),
         reverseTransitionDuration: const Duration(milliseconds: 300),
         pageBuilder: (_, __, ___) => page,
       );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final fullRect = Offset.zero & screenSize;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;

        // Interpolate rect from tile origin → fullscreen
        final left = _lerp(originRect.left, fullRect.left, t);
        final top = _lerp(originRect.top, fullRect.top, t);
        final width = _lerp(originRect.width, fullRect.width, t);
        final height = _lerp(originRect.height, fullRect.height, t);
        final radius = _lerp(6.0, 0.0, t);

        // Background darkens as thumbnail expands
        final scrimOpacity = t.clamp(0.0, 1.0);
        // Thumbnail fades out, page content fades in — crossfade
        final thumbOpacity = (1.0 - t).clamp(0.0, 1.0);
        final contentOpacity = t.clamp(0.0, 1.0);

        return Stack(
          children: [
            // Black background
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Color.fromRGBO(0, 0, 0, scrimOpacity)),
              ),
            ),
            // Page content fades in
            Opacity(opacity: contentOpacity, child: child),
            // Thumbnail fades out while expanding
            if (thumbBytes != null && thumbOpacity > 0.001)
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: Opacity(
                  opacity: thumbOpacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: Image.memory(thumbBytes!),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
