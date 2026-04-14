import 'package:geocoding/geocoding.dart';
import 'package:photo_manager/photo_manager.dart';

class LocationService {
  static final Map<String, String?> _cache = {};
  static final Map<String, String?> _detailCache = {};
  static final Map<String, (double, double)?> _coordsCache = {};

  /// Returns the lat/lng for the asset, or null if unavailable.
  static Future<(double, double)?> getLatLng(AssetEntity asset) async {
    if (_coordsCache.containsKey(asset.id)) return _coordsCache[asset.id];

    try {
      final latLng = await asset.latlngAsync();
      if (latLng == null) {
        _coordsCache[asset.id] = null;
        return null;
      }
      final result = (latLng.latitude, latLng.longitude);
      _coordsCache[asset.id] = result;
      return result;
    } catch (_) {
      _coordsCache[asset.id] = null;
      return null;
    }
  }

  /// Returns a human-readable short location string (city · district).
  static Future<String?> getLocationName(AssetEntity asset) async {
    if (_cache.containsKey(asset.id)) return _cache[asset.id];

    final coords = await getLatLng(asset);
    if (coords == null) {
      _cache[asset.id] = null;
      return null;
    }

    final (lat, lng) = coords;
    final p = await _getPlacemark(lat, lng);

    if (p != null) {
      final parts = <String>[];
      if (p.locality != null && p.locality!.isNotEmpty) {
        parts.add(p.locality!);
      }
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      }
      if (parts.isEmpty &&
          p.administrativeArea != null &&
          p.administrativeArea!.isNotEmpty) {
        parts.add(p.administrativeArea!);
      }
      if (parts.isEmpty && p.country != null && p.country!.isNotEmpty) {
        parts.add(p.country!);
      }
      if (parts.isNotEmpty) {
        final result = parts.join(' · ');
        _cache[asset.id] = result;
        return result;
      }
    }

    final fallback = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    _cache[asset.id] = fallback;
    return fallback;
  }

  /// Returns a detailed address string (country + province + city + district + street).
  static Future<String?> getDetailedAddress(AssetEntity asset) async {
    if (_detailCache.containsKey(asset.id)) return _detailCache[asset.id];

    final coords = await getLatLng(asset);
    if (coords == null) {
      _detailCache[asset.id] = null;
      return null;
    }

    final (lat, lng) = coords;
    final p = await _getPlacemark(lat, lng);

    if (p != null) {
      final parts = <String>[];
      if (p.country != null && p.country!.isNotEmpty) {
        parts.add(p.country!);
      }
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
        parts.add(p.administrativeArea!);
      }
      if (p.locality != null &&
          p.locality!.isNotEmpty &&
          p.locality != p.administrativeArea) {
        parts.add(p.locality!);
      }
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      }
      if (p.street != null && p.street!.isNotEmpty) {
        parts.add(p.street!);
      }
      if (parts.isNotEmpty) {
        final result = parts.join('');
        _detailCache[asset.id] = result;
        return result;
      }
    }

    _detailCache[asset.id] = null;
    return null;
  }

  static final Map<String, Placemark?> _placemarkCache = {};

  static Future<Placemark?> _getPlacemark(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    if (_placemarkCache.containsKey(key)) return _placemarkCache[key];

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      final result = placemarks.isNotEmpty ? placemarks.first : null;
      _placemarkCache[key] = result;
      return result;
    } catch (_) {
      _placemarkCache[key] = null;
      return null;
    }
  }
}
