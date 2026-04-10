import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../color/app_colors.dart';
import 'spring_bottom_sheet.dart';

const _c = AppColors.dark;

/// Shows a bottom sheet with a static map image and location info.
void showLocationSheet({
  required BuildContext context,
  required String locationName,
  required double latitude,
  required double longitude,
}) {
  showSpringBottomSheet(
    context: context,
    builder: (_) => _LocationMapSheet(
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

class _LocationMapSheet extends StatelessWidget {
  final String locationName;
  final double latitude;
  final double longitude;

  const _LocationMapSheet({
    required this.locationName,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _c.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Location name header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded, color: _c.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locationName,
                    style: TextStyle(
                      color: _c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Coordinates
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const SizedBox(width: 30),
                Text(
                  '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                  style: TextStyle(color: _c.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Map preview (static map image via OpenStreetMap tile)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                              color: _c.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                    ),
                    // Center pin overlay
                    Center(
                      child: Icon(
                        Icons.location_on,
                        color: _c.primary,
                        size: 36,
                      ),
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
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _openInMaps(),
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: _c.primary,
                ),
                label: Text(
                  '在地图中打开',
                  style: TextStyle(color: _c.primary, fontSize: 15),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: _c.primary.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          SizedBox(height: 16 + bottomPadding),
        ],
      ),
    );
  }

  String _staticMapUrl() {
    // Use OpenStreetMap static map via a free tile service
    final zoom = 14;
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$latitude,$longitude'
        '&zoom=$zoom'
        '&size=600x340'
        '&maptype=mapnik';
  }

  Future<void> _openInMaps() async {
    // Try Apple Maps first on iOS, fallback to Google Maps
    final appleMaps = Uri.parse(
      'https://maps.apple.com/?ll=$latitude,$longitude&q=$locationName',
    );
    final googleMaps = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    if (await canLaunchUrl(appleMaps)) {
      await launchUrl(appleMaps, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(googleMaps, mode: LaunchMode.externalApplication);
    }
  }
}
