import 'package:exif/exif.dart';
import 'package:photo_manager/photo_manager.dart';

/// Aggregated metadata for display.
class MediaMetadata {
  final String? cameraMake;
  final String? cameraModel;
  final String? aperture;
  final String? shutterSpeed;
  final String? iso;
  final String? focalLength;
  final String? fileName;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final String? mimeType;
  final DateTime? dateTime;
  final String? lensModel;

  MediaMetadata({
    this.cameraMake,
    this.cameraModel,
    this.aperture,
    this.shutterSpeed,
    this.iso,
    this.focalLength,
    this.fileName,
    this.width,
    this.height,
    this.fileSizeBytes,
    this.mimeType,
    this.dateTime,
    this.lensModel,
  });

  /// Human-readable device string, e.g. "Apple iPhone 15 Pro"
  String? get deviceName {
    if (cameraMake == null && cameraModel == null) return null;
    final make = cameraMake ?? '';
    final model = cameraModel ?? '';
    // Avoid duplication like "Apple Apple iPhone 15"
    if (model.toLowerCase().startsWith(make.toLowerCase())) return model;
    return '$make $model'.trim();
  }

  /// e.g. "2028 × 2704"
  String? get resolution {
    if (width == null || height == null) return null;
    return '$width × $height';
  }

  /// e.g. "1.3 MB"
  String? get fileSizeStr {
    if (fileSizeBytes == null) return null;
    final bytes = fileSizeBytes!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  bool get hasExifParams =>
      aperture != null ||
      shutterSpeed != null ||
      iso != null ||
      focalLength != null;
}

class ExifService {
  static final Map<String, MediaMetadata> _cache = {};

  static Future<MediaMetadata> getMetadata(AssetEntity asset) async {
    if (_cache.containsKey(asset.id)) return _cache[asset.id]!;

    String? cameraMake;
    String? cameraModel;
    String? aperture;
    String? shutterSpeed;
    String? iso;
    String? focalLength;
    String? lensModel;

    // Try reading EXIF from file
    try {
      final file = await asset.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        final tags = await readExifFromBytes(bytes);

        cameraMake = _tagStr(tags, 'Image Make');
        cameraModel = _tagStr(tags, 'Image Model');
        lensModel = _tagStr(tags, 'EXIF LensModel');

        // Aperture: FNumber tag
        final fNum = tags['EXIF FNumber'];
        if (fNum != null) {
          final val = _ratioToDouble(fNum.toString());
          if (val != null) aperture = 'f${val.toStringAsFixed(1)}';
        }

        // Shutter speed: ExposureTime
        final exposure = tags['EXIF ExposureTime'];
        if (exposure != null) {
          shutterSpeed = '${exposure.toString()} s';
        }

        // ISO
        final isoTag = tags['EXIF ISOSpeedRatings'];
        if (isoTag != null) {
          iso = 'ISO ${isoTag.toString()}';
        }

        // Focal length
        final fl = tags['EXIF FocalLength'];
        if (fl != null) {
          final val = _ratioToDouble(fl.toString());
          if (val != null) focalLength = '${val.round()} mm';
        }
      }
    } catch (_) {
      // EXIF reading failed, continue with basic info
    }

    // Get file size
    int? fileSizeBytes;
    try {
      final file = await asset.file;
      if (file != null) {
        fileSizeBytes = await file.length();
      }
    } catch (_) {}

    final meta = MediaMetadata(
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      aperture: aperture,
      shutterSpeed: shutterSpeed,
      iso: iso,
      focalLength: focalLength,
      lensModel: lensModel,
      fileName: asset.title,
      width: asset.width,
      height: asset.height,
      fileSizeBytes: fileSizeBytes,
      mimeType: asset.mimeType,
      dateTime: asset.createDateTime,
    );

    _cache[asset.id] = meta;
    return meta;
  }

  static String? _tagStr(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;
    final s = tag.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _ratioToDouble(String s) {
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 2) {
        final a = double.tryParse(parts[0].trim());
        final b = double.tryParse(parts[1].trim());
        if (a != null && b != null && b != 0) return a / b;
      }
    }
    return double.tryParse(s);
  }
}
