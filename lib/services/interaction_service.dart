import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages likes, comments, and share counts per media asset (by asset ID).
class InteractionService {
  static late SharedPreferences _prefs;
  static const String _likesKey = 'likes';
  static const String _commentsKey = 'comments';
  static const String _sharesKey = 'shares';
  static const String _dislikesKey = 'dislikes';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Likes ──

  static Map<String, int> _getLikesMap() {
    final raw = _prefs.getString(_likesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        // Handle migration from old bool format to new int format
        return decoded.map((key, value) {
          if (value is int) return MapEntry(key as String, value);
          if (value is bool) return MapEntry(key as String, value ? 1 : 0);
          return MapEntry(key as String, 0);
        });
      }
    } catch (_) {}
    return {};
  }

  static void _saveLikesMap(Map<String, int> map) {
    _prefs.setString(_likesKey, jsonEncode(map));
  }

  static int getLikeCount(String assetId) => _getLikesMap()[assetId] ?? 0;

  static bool isLiked(String assetId) => getLikeCount(assetId) > 0;

  /// Add one like (cumulative).
  static void addLike(String assetId) {
    final map = _getLikesMap();
    map[assetId] = (map[assetId] ?? 0) + 1;
    _saveLikesMap(map);
  }

  /// Remove one like. Won't go below 0.
  static void removeLike(String assetId) {
    final map = _getLikesMap();
    final current = map[assetId] ?? 0;
    if (current <= 1) {
      map.remove(assetId);
    } else {
      map[assetId] = current - 1;
    }
    _saveLikesMap(map);
  }

  // ── Comments ──

  static List<CommentItem> getComments(String assetId) {
    final raw = _prefs.getString('${_commentsKey}_$assetId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => CommentItem.fromJson(e)).toList();
  }

  static void addComment(String assetId, String text) {
    final comments = getComments(assetId);
    comments.add(CommentItem(text: text, time: DateTime.now()));
    _prefs.setString(
      '${_commentsKey}_$assetId',
      jsonEncode(comments.map((e) => e.toJson()).toList()),
    );
  }

  static int getCommentCount(String assetId) => getComments(assetId).length;

  // ── Shares ──

  static int getShareCount(String assetId) {
    final map = _getSharesMap();
    return map[assetId] ?? 0;
  }

  static void incrementShare(String assetId) {
    final map = _getSharesMap();
    map[assetId] = (map[assetId] ?? 0) + 1;
    _prefs.setString(_sharesKey, jsonEncode(map));
  }

  static Map<String, int> _getSharesMap() {
    final raw = _prefs.getString(_sharesKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  // ── Dislikes ──

  static Set<String> _getDislikesSet() {
    final raw = _prefs.getStringList(_dislikesKey);
    return raw?.toSet() ?? {};
  }

  static bool isDisliked(String assetId) => _getDislikesSet().contains(assetId);

  static void markDislike(String assetId) {
    final set = _getDislikesSet()..add(assetId);
    _prefs.setStringList(_dislikesKey, set.toList());
  }

  static void removeDislike(String assetId) {
    final set = _getDislikesSet()..remove(assetId);
    _prefs.setStringList(_dislikesKey, set.toList());
  }

  /// Returns all asset IDs that have been liked (count > 0).
  static Map<String, int> getAllLiked() {
    return Map.fromEntries(_getLikesMap().entries.where((e) => e.value > 0));
  }

  /// Returns all asset IDs that have been disliked.
  static Set<String> getAllDisliked() => _getDislikesSet();

  /// Returns all asset IDs that have been shared (count > 0).
  static Map<String, int> getAllShared() {
    return Map.fromEntries(_getSharesMap().entries.where((e) => e.value > 0));
  }
}

class CommentItem {
  final String text;
  final DateTime time;

  CommentItem({required this.text, required this.time});

  Map<String, dynamic> toJson() => {
    'text': text,
    'time': time.toIso8601String(),
  };

  factory CommentItem.fromJson(Map<String, dynamic> json) =>
      CommentItem(text: json['text'], time: DateTime.parse(json['time']));
}
