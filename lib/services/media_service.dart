import 'dart:io';
import 'dart:math';
import 'package:photo_manager/photo_manager.dart';
import '../models/feed_item.dart';
import 'image_analyzer.dart';

class MediaService {
  static int _totalImages = 0;
  static int _totalVideos = 0;
  static int _totalCount = 0;
  static AssetPathEntity? _imageAlbum;
  static AssetPathEntity? _videoAlbum;

  /// Shuffled index lists — the key to true randomization.
  static List<int> _imageIndices = [];
  static List<int> _videoIndices = [];
  static int _imagePointer = 0;
  static int _videoPointer = 0;

  static const double _similarityThreshold = 0.4;
  static const int _maxGroupSize = 8;

  static Future<int> init() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) return -1;

    final imageAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );
    final videoAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
    );

    _totalImages = 0;
    _totalVideos = 0;

    if (imageAlbums.isNotEmpty) {
      _imageAlbum = imageAlbums.first;
      _totalImages = await _imageAlbum!.assetCountAsync;
    }
    if (videoAlbums.isNotEmpty) {
      _videoAlbum = videoAlbums.first;
      _totalVideos = await _videoAlbum!.assetCountAsync;
    }

    _totalCount = _totalImages + _totalVideos;

    // Build shuffled index arrays — this is instant even for 10k+ items
    final rng = Random();
    _imageIndices = List.generate(_totalImages, (i) => i)..shuffle(rng);
    _videoIndices = List.generate(_totalVideos, (i) => i)..shuffle(rng);
    _imagePointer = 0;
    _videoPointer = 0;

    return _totalCount;
  }

  static int get totalCount => _totalCount;

  /// Load next page using globally shuffled indices.
  static Future<List<FeedItem>> loadFeedPage(
    int page, {
    int pageSize = 20,
  }) async {
    final hasImages = _imageAlbum != null && _imagePointer < _totalImages;
    final hasVideos = _videoAlbum != null && _videoPointer < _totalVideos;

    if (!hasImages && !hasVideos) return [];

    int videosToFetch;
    int imagesToFetch;

    if (hasVideos && hasImages) {
      videosToFetch = (pageSize / 3).ceil();
      videosToFetch = videosToFetch.clamp(0, _totalVideos - _videoPointer);
      imagesToFetch = pageSize - videosToFetch;
      imagesToFetch = imagesToFetch.clamp(0, _totalImages - _imagePointer);
    } else if (hasVideos) {
      videosToFetch = pageSize.clamp(0, _totalVideos - _videoPointer);
      imagesToFetch = 0;
    } else {
      imagesToFetch = pageSize.clamp(0, _totalImages - _imagePointer);
      videosToFetch = 0;
    }

    if (imagesToFetch == 0 && videosToFetch == 0) return [];

    // Fetch images by random indices (one by one, since indices are scattered)
    List<AssetEntity> newImages = [];
    if (imagesToFetch > 0 && _imageAlbum != null) {
      newImages = await _fetchByIndices(
        _imageAlbum!,
        _imageIndices,
        _imagePointer,
        imagesToFetch,
      );
      _imagePointer += imagesToFetch;
    }

    List<AssetEntity> newVideos = [];
    if (videosToFetch > 0 && _videoAlbum != null) {
      newVideos = await _fetchByIndices(
        _videoAlbum!,
        _videoIndices,
        _videoPointer,
        videosToFetch,
      );
      _videoPointer += videosToFetch;
    }

    // Group similar images, keep videos as singles
    final groupedImages = await _groupBySemantic(newImages);
    final videoItems = newVideos.map((v) => FeedItem.single(v)).toList();

    // Merge and shuffle one more time for good measure
    final result = [...groupedImages, ...videoItems];
    result.shuffle(Random());
    return result;
  }

  /// Fetch assets by scattered random indices.
  /// Groups consecutive indices into ranges for efficient batch loading.
  static Future<List<AssetEntity>> _fetchByIndices(
    AssetPathEntity album,
    List<int> indices,
    int pointer,
    int count,
  ) async {
    final selected = indices.sublist(pointer, pointer + count);
    // Sort for efficient range-based fetching
    final sorted = List<int>.from(selected)..sort();

    // Group into consecutive ranges
    final List<AssetEntity> results = [];
    int i = 0;
    while (i < sorted.length) {
      int start = sorted[i];
      int end = start + 1;
      while (i + 1 < sorted.length && sorted[i + 1] == end) {
        i++;
        end++;
      }
      final batch = await album.getAssetListRange(start: start, end: end);
      results.addAll(batch);
      i++;
    }

    // Re-order results to match the original shuffled order
    final Map<int, AssetEntity> indexToAsset = {};
    // We need to map back: sorted indices → assets
    int ri = 0;
    final sortedCopy = List<int>.from(sorted);
    int si = 0;
    while (si < sortedCopy.length && ri < results.length) {
      indexToAsset[sortedCopy[si]] = results[ri];
      si++;
      ri++;
    }

    return selected
        .where((idx) => indexToAsset.containsKey(idx))
        .map((idx) => indexToAsset[idx]!)
        .toList();
  }

  /// Use ML Kit to analyze each image, then cluster by label similarity.
  static Future<List<FeedItem>> _groupBySemantic(
    List<AssetEntity> images,
  ) async {
    if (images.isEmpty) return [];

    final Map<String, Set<String>> labelMap = {};
    final futures = <Future<void>>[];

    for (final asset in images) {
      futures.add(() async {
        final labels = await ImageAnalyzer.analyzeAsset(asset);
        labelMap[asset.id] = labels;
      }());
    }
    await Future.wait(futures);

    final used = <String>{};
    final List<FeedItem> result = [];

    for (final asset in images) {
      if (used.contains(asset.id)) continue;

      final myLabels = labelMap[asset.id] ?? {};
      if (myLabels.isEmpty) {
        result.add(FeedItem.single(asset));
        used.add(asset.id);
        continue;
      }

      final group = <AssetEntity>[asset];
      used.add(asset.id);

      for (final other in images) {
        if (used.contains(other.id)) continue;
        if (group.length >= _maxGroupSize) break;

        final otherLabels = labelMap[other.id] ?? {};
        if (otherLabels.isEmpty) continue;

        final score = ImageAnalyzer.similarity(myLabels, otherLabels);
        if (score >= _similarityThreshold) {
          group.add(other);
          used.add(other.id);
        }
      }

      if (group.length >= 2) {
        result.add(FeedItem.group(group));
      } else {
        result.add(FeedItem.single(asset));
      }
    }

    return result;
  }

  static Future<File?> getFile(AssetEntity asset) async {
    return await asset.file;
  }
}
