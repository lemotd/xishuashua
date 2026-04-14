import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';
import '../services/location_service.dart';
import '../widgets/media_card.dart';
import '../widgets/action_bar.dart';
import '../widgets/floating_heart.dart';
import '../widgets/danmaku_overlay.dart';
import '../widgets/location_map_sheet.dart';
import '../widgets/media_info_sheet.dart';
import 'collection_page.dart';

const _c = AppColors.dark;

class CollectionDetailPage extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const CollectionDetailPage({
    super.key,
    required this.assets,
    this.initialIndex = 0,
  });

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _speedUp = false;
  MediaCardState? _activeCardState;

  final List<_HeartEntry> _hearts = [];
  int _heartIdCounter = 0;
  final GlobalKey<ActionBarState> _actionBarKey = GlobalKey();
  final GlobalKey<DanmakuOverlayState> _danmakuKey = GlobalKey();

  String? _currentLocation;
  double? _currentLat;
  double? _currentLng;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadLocation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    if (widget.assets.isEmpty) return;
    final index = _currentIndex;
    final asset = widget.assets[index.clamp(0, widget.assets.length - 1)];

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
    setState(() => _hearts.add(_HeartEntry(id: id, position: position)));
  }

  void _removeHeart(int id) {
    setState(() => _hearts.removeWhere((h) => h.id == id));
  }

  // ── Long press: edge → speed-up (video only) ──
  bool _isSpeedingUp = false;

  void _handleLongPressStart(LongPressStartDetails details) {
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    final isEdge = x < width * 0.25 || x > width * 0.75;
    final cardState = _activeCardState;

    if (isEdge && cardState != null && cardState.isVideo) {
      _isSpeedingUp = true;
      cardState.startSpeedUp();
    }
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {}

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isSpeedingUp) {
      _activeCardState?.stopSpeedUp();
      _isSpeedingUp = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final currentAsset =
        widget.assets[_currentIndex.clamp(0, widget.assets.length - 1)];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _c.background,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── PageView ──
            GestureDetector(
              onLongPressStart: _handleLongPressStart,
              onLongPressMoveUpdate: _handleLongPressMoveUpdate,
              onLongPressEnd: _handleLongPressEnd,
              child: GestureDetector(
                onDoubleTapDown: _onDoubleTap,
                onDoubleTap: () {},
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.assets.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final asset = widget.assets[index];
                    return MediaCard(
                      key: ValueKey('detail_${asset.id}'),
                      asset: asset,
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
            // ── Top bar: back button only ──
            Positioned(
              top: topPadding + 8,
              left: 12,
              child: GlassCircleButton(
                onTap: () => Navigator.pop(context),
                child: SvgPicture.asset(
                  'images/back.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    _c.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            // ── Action bar ──
            Positioned(
              right: 12,
              bottom: 140,
              child: ActionBar(
                key: _actionBarKey,
                asset: currentAsset,
                onLikeTriggered: () {
                  final size = MediaQuery.of(context).size;
                  _spawnHeart(Offset(size.width / 2, size.height / 2));
                },
                onCommentPosted: (_) {
                  _danmakuKey.currentState?.reload();
                },
              ),
            ),
            // ── Danmaku ──
            Positioned.fill(
              child: DanmakuOverlay(key: _danmakuKey, assetId: currentAsset.id),
            ),
            // ── Bottom info ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _scrubbing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: _buildBottomInfo(currentAsset),
              ),
            ),
            // ── Floating hearts ──
            ..._hearts.map(
              (h) => FloatingHeart(
                key: ValueKey(h.id),
                position: h.position,
                onComplete: () => _removeHeart(h.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInfo(AssetEntity asset) {
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
              children: [_buildLocationCapsule(), _buildDateRow(asset)],
            ),
    );

    return Stack(
      children: [
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
            child: Opacity(opacity: 0, child: content),
          ),
        ),
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
            final asset =
                widget.assets[_currentIndex.clamp(0, widget.assets.length - 1)];
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
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
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

  Widget _buildDateRow(AssetEntity asset) {
    final date = asset.createDateTime;
    final dateStr =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}'
        '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => showMediaInfoSheet(context: context, asset: asset),
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
