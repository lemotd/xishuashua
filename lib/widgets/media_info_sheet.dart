import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../color/app_colors.dart';
import '../services/exif_service.dart';
import '../services/location_service.dart';
import 'spring_bottom_sheet.dart';
import 'location_map_sheet.dart';

const _c = AppColors.dark;

void showMediaInfoSheet({
  required BuildContext context,
  required AssetEntity asset,
}) {
  showSpringBottomSheet(
    context: context,
    builder: (_) => _MediaInfoSheet(asset: asset),
  );
}

class _MediaInfoSheet extends StatefulWidget {
  final AssetEntity asset;
  const _MediaInfoSheet({required this.asset});

  @override
  State<_MediaInfoSheet> createState() => _MediaInfoSheetState();
}

class _MediaInfoSheetState extends State<_MediaInfoSheet> {
  MediaMetadata? _meta;
  String? _locationName;
  double? _lat;
  double? _lng;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meta = await ExifService.getMetadata(widget.asset);
    final locName = await LocationService.getLocationName(widget.asset);
    final coords = await LocationService.getLatLng(widget.asset);
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _locationName = locName;
      _lat = coords?.$1;
      _lng = coords?.$2;
      _loading = false;
    });
  }

  // Base text style without underline — fixes the underline issue
  // that appears when Text widgets lack a Material/Scaffold ancestor.
  static final _baseStyle = TextStyle(
    decoration: TextDecoration.none,
    decorationColor: Colors.transparent,
  );

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final date = widget.asset.createDateTime;

    return DefaultTextStyle(
      style: _baseStyle.copyWith(color: _c.textPrimary, fontSize: 14),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: _c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 16 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _c.textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildDateHeader(date),
              const SizedBox(height: 24),
              if (!_loading && _meta != null) ...[
                _buildMediaSection(),
                const SizedBox(height: 8),
                _buildDivider(),
                const SizedBox(height: 16),
                _buildFileInfoSection(),
              ],
              if (_loading)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _c.primary,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              if (!_loading && _locationName != null) ...[
                const SizedBox(height: 8),
                _buildDivider(),
                const SizedBox(height: 16),
                _buildLocationSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, color: _c.divider),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    String timeAgo;
    if (diff.inDays >= 365) {
      final years = (diff.inDays / 365).floor();
      timeAgo = '$years 年前';
    } else if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      timeAgo = '$months 个月前';
    } else if (diff.inDays >= 1) {
      timeAgo = '${diff.inDays} 天前';
    } else if (diff.inHours >= 1) {
      timeAgo = '${diff.inHours} 小时前';
    } else {
      timeAgo = '刚刚';
    }

    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekday = weekdays[date.weekday - 1];
    final fullDate =
        '${date.year}年${date.month}月${date.day}日 $weekday '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeAgo,
            style: TextStyle(
              color: _c.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fullDate,
            style: TextStyle(
              color: _c.textSecondary,
              fontSize: 15,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  /// Camera/video info section: device, lens, EXIF params, then file details.
  Widget _buildMediaSection() {
    final meta = _meta!;
    final isVideo = widget.asset.type == AssetType.video;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          _buildSectionHeader(
            icon: isVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
            title: isVideo ? '视频信息' : '相片信息',
          ),
          const SizedBox(height: 14),
          // Device name
          if (meta.deviceName != null) ...[
            Text(
              '设备',
              style: TextStyle(
                color: _c.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta.deviceName!,
              style: TextStyle(
                color: _c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
          ],
          // Lens model
          if (meta.lensModel != null) ...[
            Text(
              '镜头',
              style: TextStyle(
                color: _c.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta.lensModel!,
              style: TextStyle(
                color: _c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
          ],
          // EXIF params row
          if (meta.hasExifParams) ...[
            _buildExifParamsRow(meta),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, color: _c.textSecondary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: _c.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _buildExifParamsRow(MediaMetadata meta) {
    final params = <_ExifParam>[];
    if (meta.aperture != null) params.add(_ExifParam(meta.aperture!, '光圈'));
    if (meta.shutterSpeed != null)
      params.add(_ExifParam(meta.shutterSpeed!, '快门'));
    if (meta.iso != null) params.add(_ExifParam(meta.iso!, '感光度'));
    if (meta.focalLength != null)
      params.add(_ExifParam(meta.focalLength!, '焦距'));

    return Row(
      children: [
        for (int i = 0; i < params.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _c.divider),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    params[i].value,
                    style: TextStyle(
                      color: _c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    params[i].label,
                    style: TextStyle(
                      color: _c.textSecondary,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < params.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildFileInfoSection() {
    final meta = _meta!;
    final rows = <_InfoRow>[];

    if (meta.fileName != null) rows.add(_InfoRow('文件名', meta.fileName!));
    if (meta.resolution != null) rows.add(_InfoRow('分辨率', meta.resolution!));
    if (meta.fileSizeStr != null) rows.add(_InfoRow('文件大小', meta.fileSizeStr!));
    if (meta.mimeType != null) rows.add(_InfoRow('格式', meta.mimeType!));
    if (widget.asset.type == AssetType.video) {
      final dur = widget.asset.videoDuration;
      final m = dur.inMinutes;
      final s = dur.inSeconds % 60;
      rows.add(_InfoRow('时长', '$m:${s.toString().padLeft(2, '0')}'));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows.map((r) {
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '·',
                      style: TextStyle(
                        color: _c.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.label,
                      style: TextStyle(
                        color: _c.textSecondary,
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text(
                  r.value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(icon: Icons.near_me_rounded, title: '拍摄位置'),
          const SizedBox(height: 12),
          if (_lat != null && _lng != null)
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                showLocationSheet(
                  context: context,
                  locationName: _locationName!,
                  latitude: _lat!,
                  longitude: _lng!,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        'https://staticmap.openstreetmap.de/staticmap.php'
                        '?center=$_lat,$_lng'
                        '&zoom=14&size=600x340&maptype=mapnik',
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
                      Center(
                        child: Icon(
                          Icons.location_on,
                          color: _c.primary,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (_locationName != null)
            Text(
              _locationName!,
              style: TextStyle(
                color: _c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }
}

class _ExifParam {
  final String value;
  final String label;
  _ExifParam(this.value, this.label);
}

class _InfoRow {
  final String label;
  final String value;
  _InfoRow(this.label, this.value);
}
