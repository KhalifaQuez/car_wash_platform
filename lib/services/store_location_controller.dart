import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/store_info.dart';

enum StoreLocationState {
  idle,
  locating,
  ready,
  disabled,
  denied,
  deniedForever,
  timeout,
  mocked,
  error,
}

/// 位置只在内存用于距离计算，不持久化、不发送到服务器。
class StoreLocationController extends ChangeNotifier {
  StoreLocationState state = StoreLocationState.idle;
  LocationSample? sample;
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _services;
  Timer? _expiry;
  bool _wanted = false;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;

  String get statusText {
    if (state == StoreLocationState.ready &&
        sample != null &&
        !sample!.isFreshAt(DateTime.now())) {
      return '位置已过期，请刷新定位';
    }
    return switch (state) {
      StoreLocationState.idle => '定位未开始',
      StoreLocationState.locating => '正在获取设备位置…',
      StoreLocationState.ready => '位置已更新 · 精度约 ${sample!.accuracy.round()} 米',
      StoreLocationState.disabled => '请打开设备的定位开关',
      StoreLocationState.denied => '未授权定位，仍可浏览门店',
      StoreLocationState.deniedForever => '定位权限被关闭，请在设置中开启',
      StoreLocationState.timeout => '定位超时，未使用模拟距离',
      StoreLocationState.mocked => '检测到模拟位置，无法确认真实距离',
      StoreLocationState.error => '暂时无法定位，请重试',
    };
  }

  bool get hasFreshPosition =>
      state == StoreLocationState.ready &&
      sample?.isUsableAt(DateTime.now()) == true;

  LocationSettings _settings({bool oneShot = false}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        timeLimit: oneShot ? const Duration(seconds: 25) : null,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: oneShot ? const Duration(seconds: 25) : null,
    );
  }

  void setTracking(bool enabled) {
    if (_disposed || _wanted == enabled) return;
    _wanted = enabled;
    if (!enabled) {
      _generation++;
      _positions?.cancel();
      _positions = null;
      _services?.cancel();
      _services = null;
      _expiry?.cancel();
      _expiry = null;
      sample = null;
      state = StoreLocationState.idle;
      notifyListeners();
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh({bool requestPermission = false}) async {
    if (_disposed || !_wanted || _busy) return;
    _busy = true;
    final generation = ++_generation;
    bool current() => !_disposed && _wanted && generation == _generation;
    try {
      await _positions?.cancel();
      _positions = null;
      sample = null;
      _setState(StoreLocationState.locating);
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!current()) return;
      if (!enabled) {
        _setState(StoreLocationState.disabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!current()) return;
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
        if (!current()) return;
      }
      if (permission == LocationPermission.deniedForever) {
        _setState(StoreLocationState.deniedForever);
        return;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _setState(StoreLocationState.denied);
        return;
      }

      if (!kIsWeb) {
        _services ??= Geolocator.getServiceStatusStream().listen(
          (status) {
            if (_disposed || !_wanted) return;
            if (status == ServiceStatus.disabled) {
              _generation++;
              _positions?.cancel();
              _positions = null;
              sample = null;
              _setState(StoreLocationState.disabled);
            } else {
              unawaited(refresh());
            }
          },
          onError: (Object error) {
            /* 主动刷新仍可用。 */
          },
        );
      }
      _expiry ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_disposed && _wanted) notifyListeners();
      });
      _positions = Geolocator.getPositionStream(locationSettings: _settings())
          .listen(
            (position) {
              if (current()) _accept(position);
            },
            onError: (Object error) {
              if (current()) {
                sample = null;
                _setState(StoreLocationState.error);
              }
            },
          );
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: _settings(oneShot: true),
        );
        if (current() &&
            (sample == null || position.timestamp.isAfter(sample!.timestamp)))
          _accept(position);
      } on TimeoutException {
        if (current() && !hasFreshPosition)
          _setState(StoreLocationState.timeout);
        // 仍等待前台位置流，后续有效位置会恢复距离。
      }
    } catch (_) {
      if (current() && !hasFreshPosition) {
        sample = null;
        _setState(StoreLocationState.error);
      }
    } finally {
      _busy = false;
      // 停止/返回发生在一次定位等待期间时，重新启动当前请求。
      if (!_disposed && _wanted && generation != _generation) {
        unawaited(refresh());
      }
    }
  }

  void _accept(Position position) {
    final next = LocationSample(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      isMocked: position.isMocked,
    );
    if (sample != null && next.timestamp.isBefore(sample!.timestamp)) return;
    sample = next;
    _setState(
      next.isMocked
          ? StoreLocationState.mocked
          : next.isUsableAt(DateTime.now())
          ? StoreLocationState.ready
          : StoreLocationState.error,
    );
  }

  void _setState(StoreLocationState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  Future<void> openSettings() async {
    if (kIsWeb) return;
    try {
      if (state == StoreLocationState.disabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {
      _setState(StoreLocationState.error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wanted = false;
    _generation++;
    _positions?.cancel();
    _services?.cancel();
    _expiry?.cancel();
    super.dispose();
  }
}
