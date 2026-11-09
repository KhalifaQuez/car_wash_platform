import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 单设备本地演示：使用系统加密存储，不是服务器账号数据库。
/// 不保存会话令牌，也不自动填充密码。
class AccountStorage {
  static const _key = 'car_wash_demo_accounts_v1';
  static const _storage = FlutterSecureStorage();

  static Future<String?> read() => _storage.read(key: _key);
  static Future<void> write(String value) =>
      _storage.write(key: _key, value: value);
}
