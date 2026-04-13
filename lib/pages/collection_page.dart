import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';

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
              children: [
                SizedBox(height: topPadding),
                // Nav bar: 56px
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      _GlassCircleButton(
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

const _accent = Color(0xFFFFA30F);

class _GlassCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _GlassCircleButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── Custom tab bar with full-width underline ──

class _CustomTabBar extends StatelessWidget {
  final TabController controller;

  const _CustomTabBar({required this.controller});

  static const _labels = ['不喜欢', '喜欢', '分享过'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) {
        final animValue = controller.animation!.value;
        return SizedBox(
          height: 48,
          child: Row(
            children: List.generate(_labels.length, (i) {
              final distance = (animValue - i).abs();
              final progress = (1.0 - distance).clamp(0.0, 1.0);

              return Expanded(
                child: GestureDetector(
                  onTap: () => controller.animateTo(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _labels[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: progress > 0.5
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: Color.lerp(
                            _c.textSecondary,
                            _accent,
                            progress,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 2.5,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: progress),
                          borderRadius: BorderRadius.circular(1.25),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
        return _GridTile(item: items[index], isLike: isLike);
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  final _GridItem item;
  final bool isLike;
  const _GridTile({required this.item, required this.isLike});

  String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: item.asset.thumbnailDataWithSize(const ThumbnailSize(300, 400)),
      builder: (context, snapshot) {
        return Container(
          color: _c.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail
              if (snapshot.hasData && snapshot.data != null)
                Image.memory(snapshot.data!, fit: BoxFit.cover)
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
              // Bottom gradient for readability
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
              // Count badge
              Positioned(
                left: 6,
                bottom: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLike ? Icons.favorite : Icons.reply,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatCount(item.count),
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
        );
      },
    );
  }
}
