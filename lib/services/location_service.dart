import 'package:geocoding/geocoding.dart';
import 'package:photo_manager/photo_manager.dart';

class LocationService {
  // Simple in-memory cache keyed by asset id
  static final Map<String, String?> _cache = {};

  /// Returns a human-readable location string for the asset, or null.
  static Future<String?> getLocationName(AssetEntity asset) async {
    if (_cache.containsKey(asset.id)) return _cache[asset.id];

    try {
      final latLng = await asset.latlngAsync();
      final lat = latLng?.latitude ?? 0;
      final lng = latLng?.longitude ?? 0;

      if (lat == 0 && lng == 0) {
        _cache[asset.id] = null;
        return null;
      }

      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) {
        _cache[asset.id] = null;
        return null;
      }

      final p = placemarks.first;
      // Build a concise location string
      final parts = <String>[];
      if (p.locality != null && p.locality!.isNotEmpty) {
        parts.add(p.locality!);
      }
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      }
      if (parts.isEmpty && p.administrativeArea != null) {
        parts.add(p.administrativeArea!);
      }
      if (parts.isEmpty && p.country != null) {
        parts.add(p.country!);
      }

      final result = parts.isEmpty ? null : parts.join(' · ');
      _cache[asset.id] = result;
      return result;
    } catch (_) {
      _cache[asset.id] = null;
      return null;
    }
  }

  /// Returns the lat/lng for the asset, or null if unavailable.
  static Future<(double, double)?> getLatLng(AssetEntity asset) async {
    try {
      final latLng = await asset.latlngAsync();
      final lat = latLng?.latitude ?? 0;
      final lng = latLng?.longitude ?? 0;
      if (lat == 0 && lng == 0) return null;
      return (lat, lng);
    } catch (_) {
      return null;
    }
  }
}
