import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:photo_manager/photo_manager.dart';

/// Analyzes images using ML Kit to extract semantic labels.
/// Labels represent scene/content understanding: landscape, food, pet, person, etc.
class ImageAnalyzer {
  static final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.5),
  );

  /// Analyze a single asset and return its semantic labels.
  /// Returns a set of label strings like {"Sky", "Building", "Person", "Food"}.
  static Future<Set<String>> analyzeAsset(AssetEntity asset) async {
    try {
      final File? file = await asset.file;
      if (file == null) return {};

      final inputImage = InputImage.fromFile(file);
      final labels = await _labeler.processImage(inputImage);

      return labels.map((l) => l.label).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Analyze from thumbnail bytes (faster, avoids loading full file).
  static Future<Set<String>> analyzeFromBytes(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    try {
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
      final labels = await _labeler.processImage(inputImage);
      return labels.map((l) => l.label).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Calculate similarity score between two label sets.
  /// Returns 0.0 to 1.0 (Jaccard similarity).
  static double similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 0.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return intersection / union;
  }

  static void dispose() {
    _labeler.close();
  }
}
