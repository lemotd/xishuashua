import 'dart:math';

/// 高德地图 Web 服务 API Key
const String amapWebKey = '213f668597a8fcacf399f987f22b1c27';

/// 生成高德静态地图 URL
/// 文档：https://lbs.amap.com/api/webservice/guide/api/staticmaps
String amapStaticMapUrl({
  required double latitude,
  required double longitude,
  int zoom = 15,
  String size = '600*300',
  int scale = 2,
}) {
  // 照片 GPS 是 WGS-84，高德使用 GCJ-02，需要转换
  final gcj = wgs84ToGcj02(latitude, longitude);
  final location = '${gcj.$2},${gcj.$1}'; // 经度,纬度
  return 'https://restapi.amap.com/v3/staticmap'
      '?location=$location'
      '&zoom=$zoom'
      '&size=$size'
      '&scale=$scale'
      '&markers=mid,0x8370FF,A:$location'
      '&key=$amapWebKey';
}

/// 获取 GCJ-02 坐标（供外部使用，如打开高德地图）
(double lat, double lng) toGcj02(double lat, double lng) =>
    wgs84ToGcj02(lat, lng);

// ── WGS-84 → GCJ-02 坐标转换 ──

const double _a = 6378245.0; // 长半轴
const double _ee = 0.00669342162296594323; // 偏心率平方

(double lat, double lng) wgs84ToGcj02(double wgsLat, double wgsLng) {
  if (_outOfChina(wgsLat, wgsLng)) return (wgsLat, wgsLng);

  double dLat = _transformLat(wgsLng - 105.0, wgsLat - 35.0);
  double dLng = _transformLng(wgsLng - 105.0, wgsLat - 35.0);

  final radLat = wgsLat / 180.0 * pi;
  double magic = sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = sqrt(magic);

  dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
  dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * pi);

  return (wgsLat + dLat, wgsLng + dLng);
}

bool _outOfChina(double lat, double lng) {
  return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
}

double _transformLat(double x, double y) {
  double ret =
      -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
  ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret =
      300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
  ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
  return ret;
}
