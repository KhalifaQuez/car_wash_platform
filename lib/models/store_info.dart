import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';

class StoreInfo {
  final String id;
  final String name;
  final String address;
  final String referencePlace;
  final String phone;
  final String imageAsset;
  final Uint8List? imageBytes;
  // WGS84，和设备 GPS 统一。以下是演示定位参照点，不是营业门店坐标。
  final double latitude;
  final double longitude;

  const StoreInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.referencePlace,
    required this.phone,
    required this.imageAsset,
    required this.latitude,
    required this.longitude,
    this.imageBytes,
  });

  StoreInfo copyWith({String? name, String? phone, Uint8List? imageBytes}) =>
      StoreInfo(
        id: id,
        name: name ?? this.name,
        address: address,
        referencePlace: referencePlace,
        phone: phone ?? this.phone,
        imageAsset: imageAsset,
        latitude: latitude,
        longitude: longitude,
        imageBytes: imageBytes == null
            ? this.imageBytes
            : Uint8List.fromList(imageBytes).asUnmodifiableView(),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'referencePlace': referencePlace,
    'phone': phone,
    'imageAsset': imageAsset,
    'latitude': latitude,
    'longitude': longitude,
    if (imageBytes != null) 'imageBytes': base64Encode(imageBytes!),
  };
  factory StoreInfo.fromJson(Map<String, dynamic> data) {
    for (final key in [
      'id',
      'name',
      'address',
      'referencePlace',
      'phone',
      'imageAsset',
    ]) {
      if (data[key] is! String || (data[key] as String).isEmpty)
        throw const FormatException('门店资料损坏');
    }
    if (data['latitude'] is! num ||
        data['longitude'] is! num ||
        !(data['latitude'] as num).isFinite ||
        !(data['longitude'] as num).isFinite ||
        (data['latitude'] as num).abs() > 90 ||
        (data['longitude'] as num).abs() > 180 ||
        !(data['imageAsset'] as String).startsWith('assets/images/'))
      throw const FormatException('门店位置或图片损坏');
    Uint8List? bytes;
    if (data['imageBytes'] != null) {
      if (data['imageBytes'] is! String ||
          (data['imageBytes'] as String).length > 350000)
        throw const FormatException('图片过大');
      bytes = base64Decode(data['imageBytes'] as String).asUnmodifiableView();
      if (bytes.isEmpty || bytes.length > 256 * 1024)
        throw const FormatException('图片过大');
    }
    return StoreInfo(
      id: data['id'],
      name: data['name'],
      address: data['address'],
      referencePlace: data['referencePlace'],
      phone: data['phone'],
      imageAsset: data['imageAsset'],
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      imageBytes: bytes,
    );
  }
}

/// 地址是真实地标地址；门店名称、图片、电话是演示数据。
/// 坐标来源与地址核验链接见「地址与定位说明.md」。
const demoStores = <StoreInfo>[
  StoreInfo(
    id: 'taikoo',
    name: '净车 · 太古里体验店',
    address: '成都市锦江区中纱帽街8号',
    referencePlace: '太古里',
    phone: '028-0000-0001',
    imageAsset: 'assets/images/store_1.png',
    latitude: 30 + 39 / 60 + 17.16 / 3600,
    longitude: 104 + 4 / 60 + 59.55 / 3600,
  ),
  StoreInfo(
    id: 'tianfu',
    name: '净车 · 天府广场体验店',
    address: '成都市青羊区小河街1号',
    referencePlace: '成都博物馆',
    phone: '028-0000-0002',
    imageAsset: 'assets/images/store_2.png',
    latitude: 30 + 39 / 60 + 35.03 / 3600,
    longitude: 104 + 3 / 60 + 40.32 / 3600,
  ),
  StoreInfo(
    id: 'wuhou',
    name: '净车 · 武侯体验店',
    address: '成都市武侯区武侯祠大街231号',
    referencePlace: '武侯祠',
    phone: '028-0000-0003',
    imageAsset: 'assets/images/store_3.png',
    latitude: 30 + 38 / 60 + 53.9 / 3600,
    longitude: 104 + 2 / 60 + 49.3 / 3600,
  ),
  StoreInfo(
    id: 'caotang',
    name: '净车 · 草堂体验店',
    address: '成都市青羊区青华路37号',
    referencePlace: '杜甫草堂',
    phone: '028-0000-0004',
    imageAsset: 'assets/images/store_4.png',
    latitude: 30.66278,
    longitude: 104.02611,
  ),
  StoreInfo(
    id: 'huanhua',
    name: '净车 · 浣花体验店',
    address: '成都市青羊区浣花南路251号',
    referencePlace: '四川博物院',
    phone: '028-0000-0005',
    imageAsset: 'assets/images/store_5.png',
    latitude: 30 + 39 / 60 + 36.96 / 3600,
    longitude: 104 + 2 / 60 + 3.65 / 3600,
  ),
  StoreInfo(
    id: 'jinsha',
    name: '净车 · 金沙体验店',
    address: '成都市青羊区金沙遗址路2号',
    referencePlace: '金沙遗址博物馆',
    phone: '028-0000-0006',
    imageAsset: 'assets/images/store_6.png',
    latitude: 30 + 41 / 60 + 8.02 / 3600,
    longitude: 104 + 0 / 60 + 43.02 / 3600,
  ),
  StoreInfo(
    id: 'global',
    name: '净车 · 环球中心体验店',
    address: '成都市高新区天府大道北段1700号',
    referencePlace: '环球中心',
    phone: '028-0000-0007',
    imageAsset: 'assets/images/store_7.png',
    latitude: 30 + 34 / 60 + 16 / 3600,
    longitude: 104 + 3 / 60 + 39 / 3600,
  ),
];

class LocationSample {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final bool isMocked;
  const LocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.isMocked = false,
  });

  bool isFreshAt(DateTime now) {
    final age = now.difference(timestamp);
    return age >= const Duration(seconds: -5) &&
        age <= const Duration(seconds: 30);
  }

  bool isUsableAt(DateTime now) =>
      !isMocked &&
      isFreshAt(now) &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy > 0 &&
      accuracy <= 1000;
}

double straightLineMeters(double latitude, double longitude, StoreInfo store) {
  final lat1 = latitude * math.pi / 180;
  final lat2 = store.latitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLon = (store.longitude - longitude) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

String distanceLabel(LocationSample? sample, StoreInfo store, DateTime now) {
  if (sample == null || !sample.isUsableAt(now)) return '距离暂不可用';
  final meters = straightLineMeters(sample.latitude, sample.longitude, store);
  return meters < 1000
      ? '直线约 ${meters.round()} 米'
      : '直线约 ${(meters / 1000).toStringAsFixed(1)} 公里';
}
