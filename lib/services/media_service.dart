import 'dart:io';
import 'dart:math';
import 'package:photo_manager/photo_manager.dart';
import '../models/feed_item.dart';
import 'image_analyzer.dart';
import 'interaction_service.dart';

/// Unified media feed service.
///
/// Builds ONE shuffled list of lightweight descriptors covering every asset
/// on the device, guaranteeing equal chance for photos and videos, no
/// duplicates, and true random distribution. Liked / shared items are
/// periodically re-injected at gentle intervals.
class MediaService {
  // ── Album handles ──
  static AssetPathEntity? _imageAlbum;
  static AssetPathEntity? _videoAlbum;

  // ── Unified shuffled pool ──
  static final List<_AssetRef> _pool = [];
  static int _pointer = 0;
  static int _totalCount = 0;

  // ── Semantic grouping config ──
  static const double _similarityThreshold = 0.4;
  static const int _maxGroupSize = 8;

  // ── Replay boost for liked / shared items ──
  static final List<String> _replayQueue = [];
  static int _replayPointer = 0;
  static const int _replayGapMin = 15;
  static const int _replayGapMax = 40;
  static int _itemsSinceLastReplay = 0;
  static int _nextReplayAt = 0;
  static final Set<String> _replayedThisSession = {};

  static int get totalCount => _totalCount;
  static int get remaining => (_totalCount - _pointer).clamp(0, _totalCount);

  // ────────────────────────────────────────────────────────────────────────
  // Init
  // ────────────────────────────────────────────────────────────────────────

  static Future<int> init() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
    if (!permission.hasAccess) return -1;

    final imageAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );
    final videoAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
    );

    int totalImages = 0;
    int totalVideos = 0;
    _imageAlbum = null;
    _videoAlbum = null;

    if (imageAlbums.isNotEmpty) {
      _imageAlbum = imageAlbums.first;
      totalImages = await _imageAlbum!.assetCountAsync;
    }
    if (videoAlbums.isNotEmpty) {
      _videoAlbum = videoAlbums.first;
      totalVideos = await _videoAlbum!.assetCountAsync;
    }

    _totalCount = totalImages + totalVideos;

    // Build unified pool: one entry per asset
    _pool.clear();
    for (int i = 0; i < totalImages; i++) {
      _pool.add(_AssetRef(album: _imageAlbum!, index: i, isVideo: false));
    }
    for (int i = 0; i < totalVideos; i++) {
      _pool.add(_AssetRef(album: _videoAlbum!, index: i, isVideo: true));
    }

    final rng = Random();
    _pool.shuffle(rng);
    _pointer = 0;

    // ── Build replay queue from liked / shared assets ──
    _replayQueue.clear();
    _replayPointer = 0;
    _replayedThisSession.clear();
    _itemsSinceLastReplay = 0;
    _nextReplayAt =
        _replayGapMin + rng.nextInt(_replayGapMax - _replayGapMin + 1);

    final liked = InteractionService.getAllLiked();
    final shared = InteractionService.getAllShared();
    final disliked = InteractionService.getAllDisliked();

    // score = likes + shares × 2 (sharing is a stronger signal)
    final Map<String, int> scores = {};
    for (final e in liked.entries) {
      if (disliked.contains(e.key)) continue;
      scores[e.key] = (scores[e.key] ?? 0) + e.value;
    }
    for (final e in shared.entries) {
      if (disliked.contains(e.key)) continue;
      scores[e.key] = (scores[e.key] ?? 0) + e.value * 2;
    }

    // ceil(score / 3) slots per asset, capped at 5
    for (final e in scores.entries) {
      final slots = (e.value / 3).ceil().clamp(1, 5);
      for (int i = 0; i < slots; i++) {
        _replayQueue.add(e.key);
      }
    }
    _replayQueue.shuffle(rng);

    return _totalCount;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Load page
  // ────────────────────────────────────────────────────────────────────────

  static Future<List<FeedItem>> loadFeedPage(
    int page, {
    int pageSize = 20,
  }) async {
    if (_pointer >= _pool.length) return [];

    final end = (_pointer + pageSize).clamp(0, _pool.length);
    final slice = _pool.sublist(_pointer, end);
    _pointer = end;

    if (slice.isEmpty) return [];

    // Fetch actual AssetEntity objects — batch by album
    final imageRefs = slice.where((r) => !r.isVideo).toList();
    final videoRefs = slice.where((r) => r.isVideo).toList();

    final Map<int, AssetEntity> fetchedImages = {};
    final Map<int, AssetEntity> fetchedVideos = {};

    if (imageRefs.isNotEmpty && _imageAlbum != null) {
      fetchedImages.addAll(
        await _batchFetch(_imageAlbum!, imageRefs.map((r) => r.index).toList()),
      );
    }
    if (videoRefs.isNotEmpty && _videoAlbum != null) {
      fetchedVideos.addAll(
        await _batchFetch(_videoAlbum!, videoRefs.map((r) => r.index).toList()),
      );
    }

    final disliked = InteractionService.getAllDisliked();

    final List<AssetEntity> images = [];
    final List<_ResolvedEntry> ordered = [];

    for (final ref in slice) {
      final asset = ref.isVideo
          ? fetchedVideos[ref.index]
          : fetchedImages[ref.index];
      if (asset != null && !disliked.contains(asset.id)) {
        ordered.add(_ResolvedEntry(asset: asset, isVideo: ref.isVideo));
        if (!ref.isVideo) images.add(asset);
      }
    }

    // Group images by semantic similarity
    final groupedImages = await _groupBySemantic(images);

    final Map<String, FeedItem> imageItemMap = {};
    for (final item in groupedImages) {
      for (final a in item.assets) {
        imageItemMap[a.id] = item;
      }
    }

    // Emit each FeedItem once, preserving shuffled order
    final emitted = <String>{};
    final List<FeedItem> result = [];

    for (final entry in ordered) {
      final id = entry.asset.id;
      if (emitted.contains(id)) continue;

      if (entry.isVideo) {
        result.add(FeedItem.single(entry.asset));
        emitted.add(id);
      } else {
        final item = imageItemMap[id];
        if (item != null) {
          result.add(item);
          for (final a in item.assets) {
            emitted.add(a.id);
          }
        }
      }
    }

    return _injectReplays(result);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Replay injection
  // ────────────────────────────────────────────────────────────────────────

  /// Insert at most 1 replay item per page, at a random position in the
  /// back half of the list, only after a randomized gap of 15–40 items.
  static Future<List<FeedItem>> _injectReplays(List<FeedItem> items) async {
    if (_replayQueue.isEmpty || _replayPointer >= _replayQueue.length) {
      _itemsSinceLastReplay += items.length;
      return items;
    }

    final rng = Random();
    final result = List<FeedItem>.from(items);
    _itemsSinceLastReplay += items.length;

    if (_itemsSinceLastReplay >= _nextReplayAt) {
      final asset = await _pickNextReplay();
      if (asset != null) {
        final lo = (result.length * 0.4).round().clamp(0, result.length);
        final range = (result.length - lo).clamp(1, 100);
        final insertAt = (lo + rng.nextInt(range)).clamp(0, result.length);
        result.insert(insertAt, FeedItem.single(asset));
        _itemsSinceLastReplay = 0;
        _nextReplayAt =
            _replayGapMin + rng.nextInt(_replayGapMax - _replayGapMin + 1);
      }
    }

    return result;
  }

  /// Pick the next valid replay candidate from the queue.
  static Future<AssetEntity?> _pickNextReplay() async {
    final disliked = InteractionService.getAllDisliked();

    while (_replayPointer < _replayQueue.length) {
      final id = _replayQueue[_replayPointer];
      _replayPointer++;

      if (_replayedThisSession.contains(id)) continue;
      if (disliked.contains(id)) continue;

      final asset = await AssetEntity.fromId(id);
      if (asset == null) continue;

      _replayedThisSession.add(id);
      return asset;
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Batch fetch
  // ────────────────────────────────────────────────────────────────────────

  static Future<Map<int, AssetEntity>> _batchFetch(
    AssetPathEntity album,
    List<int> indices,
  ) async {
    if (indices.isEmpty) return {};

    final sorted = List<int>.from(indices)..sort();
    final Map<int, AssetEntity> result = {};

    int i = 0;
    while (i < sorted.length) {
      int start = sorted[i];
      int end = start + 1;
      while (i + 1 < sorted.length && sorted[i + 1] == end) {
        i++;
        end++;
      }
      final batch = await album.getAssetListRange(start: start, end: end);
      for (int j = 0; j < batch.length; j++) {
        result[start + j] = batch[j];
      }
      i++;
    }

    return result;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Semantic grouping
  // ────────────────────────────────────────────────────────────────────────

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

// ── Helper types ──

class _AssetRef {
  final AssetPathEntity album;
  final int index;
  final bool isVideo;
  const _AssetRef({
    required this.album,
    required this.index,
    required this.isVideo,
  });
}

class _ResolvedEntry {
  final AssetEntity asset;
  final bool isVideo;
  const _ResolvedEntry({required this.asset, required this.isVideo});
}
