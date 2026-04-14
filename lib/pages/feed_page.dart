import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';
import '../models/feed_item.dart';
import '../services/media_service.dart';
import '../services/interaction_service.dart';
import '../services/location_service.dart';
import '../widgets/media_card.dart';
import '../widgets/carousel_card.dart';
import '../widgets/action_bar.dart';
import '../widgets/floating_heart.dart';
import '../widgets/dislike_gesture_wrapper.dart';
import '../widgets/danmaku_overlay.dart';
import '../widgets/location_map_sheet.dart';
import '../widgets/media_info_sheet.dart';
import 'collection_page.dart';

const _c = AppColors.dark;

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<FeedItem> _items = [];
  bool _loading = true;
  bool _permissionDenied = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int _currentIndex = 0;
  static const int _pageSize = 20;
  static const int _preloadThreshold = 5;

  final List<_HeartEntry> _hearts = [];
  int _heartIdCounter = 0;
  bool _speedUp = false;
  final GlobalKey<ActionBarState> _actionBarKey = GlobalKey();
  final GlobalKey<DislikeGestureWrapperState> _dislikeKey = GlobalKey();
  final GlobalKey<DanmakuOverlayState> _danmakuKey = GlobalKey();
  bool _isSpeedingUp = false;
  bool _dislikeActive = false;

  // Track the active MediaCardState via a callback instead of a GlobalKey
  // to avoid key-switching which destroys and recreates State on every page change.
  MediaCardState? _activeCardState;
  final PageController _pageController = PageController();
  AssetEntity? _carouselCurrentAsset;

  /// Remembers which slide index the user was on for each group FeedItem,
  /// so that scrolling away and back restores the correct slide & date.
  final Map<String, int> _carouselPageIndex = {};

  // Location info for current item
  String? _currentLocation;
  double? _currentLat;
  double? _currentLng;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await InteractionService.init();
    final total = await MediaService.init();
    if (total <= 0) {
      setState(() {
        _loading = false;
        _permissionDenied = total < 0;
      });
      return;
    }
    await _loadNextPage();
    setState(() => _loading = false);
    _loadLocationForCurrentItem();
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final newItems = await MediaService.loadFeedPage(
      _currentPage,
      pageSize: _pageSize,
    );
    if (newItems.isEmpty || MediaService.remaining <= 0) {
      _hasMore = newItems.isNotEmpty; // still show what we got, but stop after
    }
    if (newItems.isNotEmpty) {
      _currentPage++;
      setState(() => _items.addAll(newItems));
    }
    _loadingMore = false;
  }

  void _onPageChanged(int index) {
    final item = _items[index.clamp(0, _items.length - 1)];
    final savedSlide = item.isGroup ? _carouselPageIndex[item.id] : null;
    setState(() {
      _currentIndex = index;
      _carouselCurrentAsset = (savedSlide != null)
          ? item.assets[savedSlide]
          : null;
    });
    if (_hasMore && index >= _items.length - _preloadThreshold) {
      _loadNextPage();
    }
    _loadLocationForCurrentItem();
  }

  Future<void> _loadLocationForCurrentItem() async {
    if (_items.isEmpty) return;
    final index = _currentIndex;
    final item = _items[index.clamp(0, _items.length - 1)];
    final asset = item.primary;

    setState(() {
      _currentLocation = null;
      _currentLat = null;
      _currentLng = null;
    });

    final coords = await LocationService.getLatLng(asset);
    final name = await LocationService.getLocationName(asset);

    if (!mounted || _currentIndex != index) return;
    setState(() {
      _currentLocation = name;
      _currentLat = coords?.$1;
      _currentLng = coords?.$2;
    });
  }

  void _onDoubleTap(TapDownDetails details) {
    _actionBarKey.currentState?.triggerLike();
    _spawnHeart(details.globalPosition);
  }

  void _spawnHeart(Offset position) {
    final id = _heartIdCounter++;
    setState(() {
      _hearts.add(_HeartEntry(id: id, position: position));
    });
  }

  void _removeHeart(int id) {
    setState(() {
      _hearts.removeWhere((h) => h.id == id);
    });
  }

  void _onDislike() {
    if (_items.isEmpty) return;
    final idx = _currentIndex.clamp(0, _items.length - 1);
    final item = _items[idx];

    if (item.isGroup && _carouselCurrentAsset != null) {
      // Group: only remove the current slide, not the whole group
      final asset = _carouselCurrentAsset!;
      InteractionService.markDislike(asset.id);
      setState(() {
        item.assets.removeWhere((a) => a.id == asset.id);
        _carouselCurrentAsset = null;
        // If group is now empty, remove the whole item
        if (item.assets.isEmpty) {
          _items.removeAt(idx);
          if (_currentIndex >= _items.length && _items.isNotEmpty) {
            _currentIndex = _items.length - 1;
          }
        }
      });
    } else {
      // Single item: remove entirely
      InteractionService.markDislike(item.id);
      setState(() {
        _items.removeAt(idx);
        if (_items.isNotEmpty && _currentIndex >= _items.length) {
          _currentIndex = _items.length - 1;
        }
      });
    }

    if (_items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
        _loadLocationForCurrentItem();
      });
    }
  }

  // ── Long press routing: edge → speed-up (video only), center → dislike ──

  void _handleLongPressStart(LongPressStartDetails details) {
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    final isEdge = x < width * 0.25 || x > width * 0.75;
    final cardState = _activeCardState;

    if (isEdge && cardState != null && cardState.isVideo) {
      _isSpeedingUp = true;
      cardState.startSpeedUp();
    } else {
      _isSpeedingUp = false;
      _dislikeKey.currentState?.onLongPressStart(details);
    }
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_isSpeedingUp) return; // speed-up doesn't need move updates
    _dislikeKey.currentState?.onLongPressMoveUpdate(details);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isSpeedingUp) {
      _activeCardState?.stopSpeedUp();
      _isSpeedingUp = false;
    } else {
      _dislikeKey.currentState?.onLongPressEnd(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _c.primary),
              const SizedBox(height: 16),
              Text('正在加载相册...', style: TextStyle(color: _c.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (_permissionDenied || _items.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 80,
                  color: _c.textHint,
                ),
                const SizedBox(height: 24),
                Text(
                  '需要相册访问权限',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '请在系统设置中允许喜刷刷访问您的照片和视频',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _c.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => PhotoManager.openSetting(),
                  icon: const Icon(Icons.settings),
                  label: const Text('打开设置'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _c.primary,
                    foregroundColor: _c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _init();
                  },
                  child: Text('重新加载', style: TextStyle(color: _c.primary)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentItem = _items[_currentIndex.clamp(0, _items.length - 1)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: _dislikeActive
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              leading: Builder(
                builder: (ctx) {
                  return IconButton(
                    icon: SvgPicture.asset(
                      'images/collection.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        _c.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: () {
                      final box = ctx.findRenderObject() as RenderBox;
                      final rect = box.localToGlobal(Offset.zero) & box.size;
                      Navigator.push(
                        context,
                        _CollectionExpandRoute(
                          page: const CollectionPage(),
                          originRect: rect,
                        ),
                      );
                    },
                  );
                },
              ),
              title: Text(
                '喜刷刷',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _c.textPrimary,
                ),
              ),
            ),
      body: Stack(
        children: [
          // PageView wrapped in DislikeGestureWrapper — only this shrinks
          GestureDetector(
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: DislikeGestureWrapper(
              key: _dislikeKey,
              onDislike: _onDislike,
              onActiveChanged: (active) =>
                  setState(() => _dislikeActive = active),
              child: GestureDetector(
                onDoubleTapDown: _onDoubleTap,
                onDoubleTap: () {},
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  physics: _dislikeKey.currentState?.active == true
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: _items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    if (item.isGroup) {
                      final savedPage = _carouselPageIndex[item.id] ?? 0;
                      return CarouselCard(
                        key: ValueKey('group_${item.id}'),
                        assets: item.assets,
                        initialPage: savedPage,
                        onSlideChanged: index == _currentIndex
                            ? (asset) {
                                final slideIdx = item.assets.indexOf(asset);
                                if (slideIdx >= 0) {
                                  _carouselPageIndex[item.id] = slideIdx;
                                }
                                setState(() => _carouselCurrentAsset = asset);
                              }
                            : (asset) {
                                // Even when not the active page, remember the
                                // slide index so we can restore it later.
                                final slideIdx = item.assets.indexOf(asset);
                                if (slideIdx >= 0) {
                                  _carouselPageIndex[item.id] = slideIdx;
                                }
                              },
                      );
                    }
                    return MediaCard(
                      key: ValueKey('media_${item.id}'),
                      asset: item.primary,
                      isActive: index == _currentIndex,
                      onSpeedChanged: (v) => setState(() => _speedUp = v),
                      onScrubbingChanged: (v) => setState(() => _scrubbing = v),
                      onStateCreated: index == _currentIndex
                          ? (state) => _activeCardState = state
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
          // UI overlays — hidden during dislike gesture
          if (!_dislikeActive)
            Positioned(
              right: 12,
              bottom: 140,
              child: ActionBar(
                key: _actionBarKey,
                asset: currentItem.primary,
                onLikeTriggered: () {
                  final size = MediaQuery.of(context).size;
                  _spawnHeart(Offset(size.width / 2, size.height / 2));
                },
                onCommentPosted: (text) {
                  _danmakuKey.currentState?.addOne(text);
                },
              ),
            ),
          // Danmaku overlay — always visible when there are comments
          Positioned.fill(
            child: DanmakuOverlay(
              key: _danmakuKey,
              assetId: currentItem.primary.id,
            ),
          ),
          if (!_dislikeActive)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _scrubbing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: _buildBottomInfo(),
              ),
            ),
          ..._hearts.map(
            (h) => FloatingHeart(
              key: ValueKey(h.id),
              position: h.position,
              onComplete: () => _removeHeart(h.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInfo() {
    if (_items.isEmpty) return const SizedBox.shrink();

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: _speedUp
          ? Row(
              key: const ValueKey('speed'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fast_forward_rounded,
                  color: _c.textPrimary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '2 倍速播放中',
                  style: TextStyle(
                    color: _c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          : Column(
              key: const ValueKey('info'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [_buildLocationCapsule(), _buildDateRow()],
            ),
    );

    return Stack(
      children: [
        // Gradient background — ignores pointer so swipes pass through
        IgnorePointer(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 76),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [_c.gradientStart, _c.gradientEnd],
              ),
            ),
            // Invisible copy to size the Stack correctly
            child: Opacity(opacity: 0, child: content),
          ),
        ),
        // Interactive content on top — only buttons intercept taps
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 76),
          child: content,
        ),
      ],
    );
  }

  Widget _buildLocationCapsule() {
    if (_currentLocation == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          if (_currentLat != null && _currentLng != null) {
            final item = _items[_currentIndex.clamp(0, _items.length - 1)];
            final asset = _carouselCurrentAsset ?? item.primary;
            showLocationSheet(
              context: context,
              asset: asset,
              locationName: _currentLocation!,
              latitude: _currentLat!,
              longitude: _currentLng!,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: SmoothBorderRadius(
              cornerRadius: 20,
              cornerSmoothing: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                color: _c.textSecondary,
                size: 14,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _currentLocation!,
                  style: TextStyle(color: _c.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    final item = _items[_currentIndex.clamp(0, _items.length - 1)];
    final asset = _carouselCurrentAsset ?? item.primary;
    final date = asset.createDateTime;
    final dateStr =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}'
        '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        showMediaInfoSheet(context: context, asset: asset);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateStr,
            style: TextStyle(color: _c.textSecondary, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: _c.textHint, size: 16),
        ],
      ),
    );
  }
}

class _HeartEntry {
  final int id;
  final Offset position;
  _HeartEntry({required this.id, required this.position});
}

// ── Custom route: expand from icon origin with scrim overlay ──

class _CollectionExpandRoute extends PageRouteBuilder {
  final Rect originRect;

  _CollectionExpandRoute({required Widget page, required this.originRect})
    : super(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        opaque: false,
        pageBuilder: (_, __, ___) => page,
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.of(context).size;

    // Curved animations
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Origin center (normalized 0..1)
    final originX = originRect.center.dx / size.width;
    final originY = originRect.center.dy / size.height;

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;

        // Scrim: dark overlay that fades in/out smoothly
        // Content opacity: delayed slightly on enter so scrim appears first
        final scrimOpacity = t.clamp(0.0, 1.0);
        final contentOpacity = Interval(0.15, 0.85).transform(t);

        // Scale: from small to full
        final scale = 0.0 + t * 1.0;

        return Stack(
          children: [
            // Dark scrim behind everything
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color.fromRGBO(0, 0, 0, 0.5 * scrimOpacity),
                ),
              ),
            ),
            // Scaled + faded page content
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40 * (1.0 - t)),
                child: Transform(
                  alignment: Alignment(
                    // Convert 0..1 to -1..1
                    originX * 2 - 1,
                    originY * 2 - 1,
                  ),
                  transform: Matrix4.identity()..scale(scale, scale),
                  child: Opacity(
                    opacity: contentOpacity.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
