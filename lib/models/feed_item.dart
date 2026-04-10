import 'package:photo_manager/photo_manager.dart';

/// A single item in the feed. Can be a single asset or a group of similar photos.
class FeedItem {
  final List<AssetEntity> assets;

  FeedItem.single(AssetEntity asset) : assets = [asset];
  FeedItem.group(this.assets);

  bool get isGroup => assets.length > 1;
  AssetEntity get primary => assets.first;
  String get id => primary.id;
}
