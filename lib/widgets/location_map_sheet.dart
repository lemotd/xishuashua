import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../color/app_colors.dart';
import '../pages/collection_page.dart' show PressableScale;
import '../services/location_service.dart';
import '../services/map_config.dart';
import 'spring_bottom_sheet.dart';

const _c = AppColors.dark;

/// Shows a bottom sheet with location info and map.
void showLocationSheet({
  required BuildContext context,
  required AssetEntity asset,
  required String locationName,
  required double latitude,
  required double longitude,
}) {
  showSpringBottomSheet(
    context: context,
    builder: (_) => _LocationMapSheet(
      asset: asset,
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

class _LocationMapSheet extends StatefulWidget {
  final AssetEntity asset;
  final String locationName;
  final double latitude;
  final double longitude;

  const _LocationMapSheet({
    required this.asset,
    required this.locationName,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<_LocationMapSheet> createState() => _LocationMapSheetState();
}

class _LocationMapSheetState extends State<_LocationMapSheet> {
  String? _detailedAddress;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final addr = await LocationService.getDetailedAddress(widget.asset);
    if (!mounted) return;
    setState(() => _detailedAddress = addr);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final accent = _c.highlightPurple;

    return DefaultTextStyle(
      style: TextStyle(
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
        color: _c.textPrimary,
        fontSize: 14,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _c.surface,
          borderRadius: const SmoothBorderRadius.vertical(
            top: SmoothRadius(cornerRadius: 20, cornerSmoothing: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _c.textHint,
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 2,
                    cornerSmoothing: 0.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Location name header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.locationName,
                style: TextStyle(
                  color: _c.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Detailed address subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _detailedAddress ?? '加载中...',
                style: TextStyle(
                  color: _c.textSecondary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Map preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipSmoothRect(
                radius: SmoothBorderRadius(
                  cornerRadius: 14,
                  cornerSmoothing: 0.6,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _staticMapUrl(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: _c.cardBackground,
                          child: Center(
                            child: Icon(
                              Icons.map_outlined,
                              color: _c.textHint,
                              size: 48,
                            ),
                          ),
                        ),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: _c.cardBackground,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: accent,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        },
                      ),
                      // Center pin
                      Center(
                        child: Icon(Icons.location_on, color: accent, size: 36),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Open in Maps button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PressableScale(
                onTap: _openInMaps,
                scaleDown: 0.95,
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: null,
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: accent,
                    ),
                    label: Text(
                      '在地图中打开',
                      style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.1),
                      disabledForegroundColor: accent,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 12,
                          cornerSmoothing: 0.6,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16 + bottomPadding),
          ],
        ),
      ),
    );
  }

  String _staticMapUrl() {
    return amapStaticMapUrl(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
  }

  Future<void> _openInMaps() async {
    // 高德地图需要 GCJ-02 坐标
    final gcj = toGcj02(widget.latitude, widget.longitude);
    final name = widget.locationName;

    // 优先尝试高德地图
    final amapUrl = Uri.parse(
      'https://uri.amap.com/marker?position=${gcj.$2},${gcj.$1}&name=$name&coordinate=gaode',
    );
    final appleMaps = Uri.parse(
      'https://maps.apple.com/?ll=${widget.latitude},${widget.longitude}&q=$name',
    );

    if (await canLaunchUrl(amapUrl)) {
      await launchUrl(amapUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleMaps)) {
      await launchUrl(appleMaps, mode: LaunchMode.externalApplication);
    }
  }
}
