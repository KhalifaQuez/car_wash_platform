import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'booking_data.dart';
import 'store_info.dart';
import 'recharge_data.dart';
import 'store_management_data.dart';
import 'service_pricing.dart';
import 'store_revenue.dart';

// 本地演示账号。数据由加密存储适配器保存，正式权限由服务器验证。
enum AccountRole { customer, administrator }

const demoAdminPhone = '11110000000';
const demoAdminPassword = 'admain'; // 按用户指定保留；仅用于本地演示。

class UserProfile {
  final String id;
  final String username;
  final String phone;
  final AccountRole role;
  final Uint8List? avatarBytes;
  final bool enabled;

  UserProfile({
    String? id,
    required this.username,
    required this.phone,
    this.role = AccountRole.customer,
    this.enabled = true,
    Uint8List? avatarBytes,
  }) : id =
           id ??
           (role == AccountRole.administrator
               ? 'administrator:demo'
               : 'customer:$phone'),
       avatarBytes = avatarBytes == null
           ? null
           : Uint8List.fromList(avatarBytes);
}

class AccountValidationException implements Exception {
  final String message;
  const AccountValidationException(this.message);
  @override
  String toString() => message;
}

String? validateUsername(String? value) {
  final length = (value ?? '').trim().runes.length;
  if (length < 2 || length > 20) return '用户名需要 2～20 个字符';
  return null;
}

String? validatePhone(String? value) {
  if (!RegExp(r'^1[3-9]\d{9}$').hasMatch((value ?? '').trim())) {
    return '请输入正确的 11 位手机号';
  }
  return null;
}

String? validateLoginPhone(String? value) =>
    (value ?? '').trim() == demoAdminPhone ? null : validatePhone(value);

String? validateRegistrationPhone(String? value) =>
    (value ?? '').trim() == demoAdminPhone
    ? '该手机号已被注册，请直接登录'
    : validatePhone(value);

String? validatePassword(String? value) {
  final length = (value ?? '').length;
  if (length < 6 || length > 32) return '密码需要 6～32 位';
  return null;
}

class _DemoAccount {
  final UserProfile profile;
  final String password;
  const _DemoAccount(this.profile, this.password);
}

/// 仅用于本地演示：验证码直接展示在界面，不会发送短信。
/// 真实服务不能把验证码返回给客户端，必须由后端验证。
class DemoPasswordResetCode {
  final String phone;
  final String code;
  final DateTime expiresAt;
  final DateTime resendAllowedAt;

  const DemoPasswordResetCode({
    required this.phone,
    required this.code,
    required this.expiresAt,
    required this.resendAllowedAt,
  });
}

class _PendingPasswordReset {
  final DemoPasswordResetCode challenge;
  int failedAttempts = 0;
  _PendingPasswordReset(this.challenge);
}

String _newDemoResetCode() =>
    Random.secure().nextInt(1000000).toString().padLeft(6, '0');

class DemoAccountStore {
  final Map<String, StoreSettings> _storeSettings = {};
  final Map<String, int> _legacyStoreNet = {};
  StoreRevenueSummary storeRevenue(
    String storeId, {
    DateTime? fromUtc,
    DateTime? toUtc,
  }) {
    requireStoreAuthorization(storeId);
    return summarizeStoreRevenue(
      storeId,
      _walletEntries,
      fromUtc: fromUtc,
      toUtc: toUtc,
      legacyNetCents: _legacyStoreNet[storeId] ?? 0,
      unattributedCount: _walletEntries
          .where(
            (e) =>
                e.storeId == null &&
                e.bookingId != null &&
                (e.kind == WalletEntryKind.payment ||
                    e.kind == WalletEntryKind.refund),
          )
          .length,
    );
  }

  String? _authorizedStoreId;
  int _authorizationGeneration = 0;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  void releaseStoreAuthorization() {
    _authorizationGeneration++;
    _authorizedStoreId = null;
  }

  void requireStoreAuthorization(String storeId) {
    _requireAdmin();
    if (_authorizedStoreId != storeId)
      throw const AccountValidationException('请先输入该门店管理代码');
  }

  Future<void> authorizeStore(String storeId, String code) {
    releaseStoreAuthorization();
    final generation = _authorizationGeneration;
    final session = _sessionRevision;
    return _serial(() async {
      _requireAdmin();
      if (generation != _authorizationGeneration || session != _sessionRevision)
        throw const AccountValidationException('门店验证已取消');
      final valid =
          storeManagementCodes[storeId] != null &&
          storeManagementCodes[storeId] == code.trim().toUpperCase();
      await _save(
        _accounts,
        _rememberedPhone,
        action: valid ? '门店管理验证成功' : '门店管理验证失败',
        detail: storeId,
      );
      _notify();
      if (!valid) throw const AccountValidationException('管理代码不正确');
      if (generation != _authorizationGeneration || session != _sessionRevision)
        throw const AccountValidationException('门店验证已取消');
      _authorizedStoreId = storeId;
    });
  }

  Future<StoreSettings> saveStoreSettings(
    StoreSettings next, {
    required int expectedRevision,
  }) => _serial(() async {
    requireStoreAuthorization(next.info.id);
    next.validate();
    final old = storeSettings(next.info.id);
    if (old.revision != expectedRevision)
      throw const AccountValidationException('门店设置已改变，请重新打开');
    final updated = StoreSettings.fromJson(
      next.copyWith(revision: old.revision + 1).toJson(),
    );
    final changes = <String>[
      if (old.info.phone != next.info.phone)
        '电话${old.info.phone}→${next.info.phone}',
      if (old.description != next.description)
        '介绍${old.description}→${next.description}',
      if (old.info.imageBytes != next.info.imageBytes) '更换展示图片',
      if (old.closedDates.difference(next.closedDates).isNotEmpty ||
          next.closedDates.difference(old.closedDates).isNotEmpty)
        '休息日${old.closedDates.join(',')}→${next.closedDates.join(',')}',
      for (final item in next.items)
        if (old.item(item.service, item.section, item.choice).cents !=
                item.cents ||
            old.item(item.service, item.section, item.choice).enabled !=
                item.enabled)
          '${item.service}/${item.choice} ${old.item(item.service, item.section, item.choice).cents}分→${item.cents}分 · 上架${old.item(item.service, item.section, item.choice).enabled}→${item.enabled}',
    ];
    await _save(
      _accounts,
      _rememberedPhone,
      storeSettings: {..._storeSettings, next.info.id: updated},
      action: '修改门店设置',
      detail:
          '${next.info.id} · ${old.info.name}→${next.info.name} · 营业${old.acceptingBookings}→${next.acceptingBookings} · 时段${old.openMinute}-${old.closeMinute}→${next.openMinute}-${next.closeMinute} · 修订${old.revision}→${updated.revision} · ${changes.join('；')}',
    );
    _notify();
    return updated;
  });
  final Map<String, _DemoAccount> _accounts = {};
  final Map<String, _PendingPasswordReset> _passwordResetCodes = {};
  final Map<String, DateTime> _resetRetryAt = {};
  final Map<String, Booking> _bookings = {};
  final List<AccountActivity> _activities = [];
  final Map<String, CardAccount> _wallets = {};
  final List<WalletEntry> _walletEntries = [];
  final Set<String> _purgedRequests = {};
  final Set<void Function()> _listeners = {};
  final DateTime Function() _now;
  final String Function() _generateResetCode;
  final Future<String?> Function()? _readState;
  final Future<void> Function(String)? _writeState;
  Future<void> _operation = Future<void>.value();
  Future<void>? _initializing;
  bool _ready;
  String? _rememberedPhone;
  UserProfile? _currentUser;
  void Function()? onChanged;

  DemoAccountStore({
    DateTime Function()? now,
    String Function()? generateResetCode,
    Future<String?> Function()? readState,
    Future<void> Function(String)? writeState,
  }) : _now = now ?? DateTime.now,
       _generateResetCode = generateResetCode ?? _newDemoResetCode,
       _readState = readState,
       // 保留公开的 writeState 命名参数，同时使用私有存储字段。
       // ignore: prefer_initializing_formals
       _writeState = writeState,
       _ready = readState == null;

  UserProfile? get currentUser => _currentUser;
  StoreSettings storeSettings(String storeId) {
    _requireReady();
    final base = demoStores.where((s) => s.id == storeId).firstOrNull;
    if (base == null) throw const AccountValidationException('门店不存在');
    return _storeSettings[storeId] ?? StoreSettings.defaults(base);
  }

  List<StoreInfo> get stores =>
      List.unmodifiable(demoStores.map((s) => storeSettings(s.id).info));
  void _checkStoreBooking(StoreSettings settings, int? expectedRevision) {
    if (!settings.acceptingBookings)
      throw const BookingValidationException('门店已关门，暂停新增或修改预约');
    if (expectedRevision != null && settings.revision != expectedRevision)
      throw const BookingValidationException('门店价格或时段已改变，请核对最新选项后重新提交');
  }

  void _checkManagedBooking(Booking booking, String? storeId) {
    if (storeId == null) return;
    requireStoreAuthorization(storeId);
    if (booking.store.id != storeId)
      throw const AccountValidationException('不能管理其他门店预约');
  }

  String? get rememberedPhone => _rememberedPhone;
  bool get isAdministrator =>
      _currentUser?.role == AccountRole.administrator &&
      _currentUser?.phone == demoAdminPhone;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notify() {
    onChanged?.call();
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _requireAdmin() {
    _requireReady();
    if (!isAdministrator) throw const AccountValidationException('仅管理员可执行此操作');
  }

  UserProfile _requireCustomer() {
    _requireReady();
    final profile = _currentUser;
    if (profile == null ||
        profile.role != AccountRole.customer ||
        !profile.enabled) {
      throw const AccountValidationException('请使用正常的用户账号登录');
    }
    return profile;
  }

  List<UserProfile> get registeredUsers {
    _requireAdmin();
    return List.unmodifiable(
      _accounts.values.map((account) => account.profile),
    );
  }

  UserProfile? userById(String id) {
    if (!isAdministrator && _currentUser?.id != id) {
      throw const AccountValidationException('无权查看其他用户资料');
    }
    for (final account in _accounts.values) {
      if (account.profile.id == id) return account.profile;
    }
    return null;
  }

  List<Booking> visibleBookings({String? ownerId, String? managedStoreId}) {
    if (managedStoreId != null) requireStoreAuthorization(managedStoreId);
    _requireReady();
    final user = _currentUser;
    if (user == null) throw const AccountValidationException('请先登录');
    if (!isAdministrator) {
      _requireCustomer();
      if (ownerId != null && ownerId != user.id) {
        throw const AccountValidationException('无权查看其他用户预约');
      }
      ownerId = user.id;
    }
    final result =
        _bookings.values
            .where(
              (booking) =>
                  (ownerId == null || booking.ownerId == ownerId) &&
                  (managedStoreId == null ||
                      booking.store.id == managedStoreId) &&
                  (isAdministrator || !booking.hiddenFromCustomer),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(result);
  }

  Booking bookingById(String id, {String? managedStoreId}) {
    _requireReady();
    final booking = _bookings[id];
    if (booking == null) throw const BookingValidationException('预约不存在');
    _checkManagedBooking(booking, managedStoreId);
    if (!isAdministrator && _requireCustomer().id != booking.ownerId) {
      throw const AccountValidationException('无权操作其他用户预约');
    }
    if (!isAdministrator && booking.hiddenFromCustomer) {
      throw const BookingValidationException('该预约已从你的列表删除');
    }
    return booking;
  }

  List<AccountActivity> get activities {
    _requireAdmin();
    return List.unmodifiable(_activities.reversed);
  }

  // 初始化只恢复账号和记住的手机号，不恢复登录状态。
  Future<void> initialize() {
    if (_ready) return Future<void>.value();
    return _initializing ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _readState!();
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map<String, dynamic> ||
            (data['version'] != 1 &&
                data['version'] != 2 &&
                data['version'] != 3 &&
                data['version'] != 4 &&
                data['version'] != 5 &&
                data['version'] != 6) ||
            data['accounts'] is! List) {
          throw const FormatException('Unsupported account data');
        }
        final restored = <String, _DemoAccount>{};
        for (final entry in data['accounts'] as List) {
          if (entry is! Map<String, dynamic> ||
              entry['phone'] is! String ||
              entry['username'] is! String ||
              entry['password'] is! String) {
            throw const FormatException('Invalid account data');
          }
          final phone = entry['phone'] as String;
          final username = entry['username'] as String;
          final password = entry['password'] as String;
          if ((entry['id'] != null && entry['id'] is! String) ||
              (entry['enabled'] != null && entry['enabled'] is! bool)) {
            throw const FormatException('Invalid user identity');
          }
          final id = entry['id'] as String? ?? 'customer:$phone';
          if (id.isEmpty ||
              id == 'administrator:demo' ||
              restored.values.any((account) => account.profile.id == id)) {
            throw const FormatException('Duplicate user identity');
          }
          if (validateRegistrationPhone(phone) != null ||
              validateUsername(username) != null ||
              validatePassword(password) != null ||
              restored.containsKey(phone)) {
            throw const FormatException('Invalid account fields');
          }
          final avatar = entry['avatar'];
          if (avatar != null && avatar is! String) {
            throw const FormatException('Invalid avatar data');
          }
          final bytes = avatar == null ? null : base64Decode(avatar as String);
          if (bytes != null && bytes.length > 3 * 1024 * 1024) {
            throw const FormatException('Avatar too large');
          }
          // 不信任存储里的角色字段；普通注册记录永远只是用户。
          restored[phone] = _DemoAccount(
            UserProfile(
              id: id,
              username: username,
              phone: phone,
              avatarBytes: bytes,
              enabled: entry['enabled'] as bool? ?? true,
            ),
            password,
          );
        }
        final remembered = data['rememberedPhone'];
        if (remembered != null &&
            (remembered is! String || validateLoginPhone(remembered) != null)) {
          throw const FormatException('Invalid remembered phone');
        }
        final restoredBookings = <String, Booking>{};
        final restoredActivities = <AccountActivity>[];
        final restoredPurgedRequests = <String>{};
        if (data['version'] == 2 ||
            data['version'] == 3 ||
            data['version'] == 4 ||
            data['version'] == 5 ||
            data['version'] == 6) {
          if (data['bookings'] is! List || data['activities'] is! List) {
            throw const FormatException('Invalid local booking database');
          }
          final userIds = restored.values
              .map((account) => account.profile.id)
              .toSet();
          final requestIds = <String>{};
          for (final entry in data['bookings'] as List) {
            if (entry is! Map<String, dynamic>) {
              throw const FormatException('Invalid booking');
            }
            final booking = Booking.fromJson(entry);
            if (!userIds.contains(booking.ownerId) ||
                restoredBookings.containsKey(booking.id) ||
                !requestIds.add('${booking.ownerId}:${booking.requestId}')) {
              throw const FormatException('Invalid booking ownership');
            }
            restoredBookings[booking.id] = booking;
          }
          for (final entry in data['activities'] as List) {
            if (entry is! Map<String, dynamic>) {
              throw const FormatException('Invalid activity');
            }
            restoredActivities.add(AccountActivity.fromJson(entry));
          }
          final purged = data['purgedRequests'];
          if (purged != null &&
              (purged is! List || purged.any((value) => value is! String))) {
            throw const FormatException('Invalid deletion markers');
          }
          if (purged is List)
            restoredPurgedRequests.addAll(purged.cast<String>());
        }
        final restoredWallets = <String, CardAccount>{};
        final restoredEntries = <WalletEntry>[];
        if (data['version'] == 4 ||
            data['version'] == 5 ||
            data['version'] == 6) {
          if (data['wallets'] is! List || data['walletEntries'] is! List) {
            throw const FormatException('资金记录损坏');
          }
          final userIds = restored.values.map((a) => a.profile.id).toSet();
          final transactionIds = <String>{};
          final requestIds = <String>{};
          for (final value in data['wallets'] as List) {
            if (value is! Map<String, dynamic>)
              throw const FormatException('资金记录损坏');
            final wallet = CardAccount.fromJson(value);
            if (!userIds.contains(wallet.ownerId) ||
                restoredWallets.containsKey(wallet.ownerId)) {
              throw const FormatException('资金归属损坏');
            }
            restoredWallets[wallet.ownerId] = wallet;
          }
          for (final value in data['walletEntries'] as List) {
            if (value is! Map<String, dynamic>)
              throw const FormatException('交易记录损坏');
            if ((data['version'] == 5 || data['version'] == 6) &&
                !value.containsKey('chargedCents')) {
              throw const FormatException('办卡收费记录缺失');
            }
            var entry = WalletEntry.fromJson(value);
            if (data['version'] != 6 &&
                entry.storeId == null &&
                entry.bookingId != null) {
              final order = restoredBookings[entry.bookingId];
              if (order != null)
                entry = WalletEntry.fromJson({
                  ...entry.toJson(),
                  'storeId': order.store.id,
                  'storeName': order.store.name,
                });
            }
            if (entry.storeId != null &&
                !storeManagementCodes.containsKey(entry.storeId))
              throw const FormatException('交易门店不存在');
            if (!userIds.contains(entry.ownerId) ||
                !transactionIds.add(entry.id) ||
                !requestIds.add('${entry.ownerId}:${entry.requestId}')) {
              throw const FormatException('交易归属或请求重复');
            }
            restoredEntries.add(entry);
          }
        }
        for (final wallet in restoredWallets.values) {
          final latest = restoredEntries.reversed
              .where((e) => e.ownerId == wallet.ownerId)
              .firstOrNull;
          if (latest == null ||
              latest.balanceAfterCents != wallet.balanceCents) {
            throw const FormatException('余额与交易流水不一致');
          }
        }
        if (restoredEntries.any(
          (e) => !restoredWallets.containsKey(e.ownerId),
        )) {
          throw const FormatException('交易缺少卡账户');
        }
        for (final booking in restoredBookings.values.where(
          _unclosedCardBooking,
        )) {
          final wallet = restoredWallets[booking.ownerId];
          if (wallet == null ||
              !wallet.active ||
              wallet.cardId != booking.paymentCardId) {
            throw const FormatException('未关闭订单的付款卡不存在');
          }
        }
        final settings = <String, StoreSettings>{};
        if (data['version'] == 6) {
          if (data['storeSettings'] is! List)
            throw const FormatException('门店设置缺失');
          for (final value in data['storeSettings'] as List) {
            if (value is! Map<String, dynamic>)
              throw const FormatException('门店设置损坏');
            final config = StoreSettings.fromJson(value);
            if (settings.containsKey(config.info.id))
              throw const FormatException('门店设置重复');
            settings[config.info.id] = config;
          }
          if (settings.length != demoStores.length)
            throw const FormatException('门店设置不完整');
        }
        final legacyNet = <String, int>{};
        if (data['version'] == 6) {
          final values = data['legacyStoreNet'];
          if (values is! Map<String, dynamic> || values.length != 7)
            throw const FormatException('历史营业额基数缺失');
          for (final s in demoStores) {
            final value = values[s.id];
            if (value is! int) throw const FormatException('历史营业额基数损坏');
            validateMoney(value);
            legacyNet[s.id] = value;
          }
        } else {
          for (final order in restoredBookings.values) {
            final net = restoredEntries
                .where(
                  (e) =>
                      e.bookingId == order.id &&
                      (e.kind == WalletEntryKind.payment ||
                          e.kind == WalletEntryKind.refund),
                )
                .fold<int>(0, (n, e) => n - e.deltaCents);
            final residual = order.netPaidCents - net;
            if (residual < 0) throw const FormatException('旧订单与资金记录不一致');
            legacyNet.update(
              order.store.id,
              (v) => v + residual,
              ifAbsent: () => residual,
            );
          }
        }
        _legacyStoreNet.addAll(legacyNet);
        _storeSettings.addAll(settings);
        _wallets.addAll(restoredWallets);
        _purgedRequests
          ..clear()
          ..addAll(restoredPurgedRequests);
        _walletEntries.addAll(restoredEntries);
        _accounts.addAll(restored);
        _bookings.addAll(restoredBookings);
        _activities.addAll(restoredActivities);
        _rememberedPhone = remembered as String?;
      }
      _ready = true;
    } catch (_) {
      // 不自动清空损坏或暂时读不到的数据，避免覆盖已有账号。
      _initializing = null;
      throw const AccountValidationException('读取本地账号失败，请重试；不会自动清空原有数据');
    }
  }

  void _requireValid(String? message) {
    if (message != null) throw AccountValidationException(message);
  }

  void _requireReady() {
    if (!_ready) {
      throw const AccountValidationException('账号尚未加载完成，请稍后再试');
    }
  }

  void _checkWalletAccess(String userId) {
    _requireReady();
    if (!isAdministrator && _requireCustomer().id != userId) {
      throw const AccountValidationException('无权操作其他用户的充值卡');
    }
    if (!_accounts.values.any((a) => a.profile.id == userId)) {
      throw const AccountValidationException('用户不存在');
    }
  }

  CardAccount walletFor(String userId) {
    _checkWalletAccess(userId);
    return _wallets[userId] ?? CardAccount(ownerId: userId);
  }

  List<WalletEntry> walletEntriesFor(String userId) {
    _checkWalletAccess(userId);
    return List.unmodifiable(
      _walletEntries.reversed.where((e) => e.ownerId == userId),
    );
  }

  WalletEntry? _replayed(String ownerId, String requestId, String fingerprint) {
    if (requestId.trim().isEmpty || requestId.length > 200) {
      throw const AccountValidationException('请求标识无效');
    }
    final entry = _walletEntries
        .where((e) => e.ownerId == ownerId && e.requestId == requestId)
        .firstOrNull;
    if (entry != null &&
        (entry.fingerprint != fingerprint ||
            entry.actorId != _currentUser!.id)) {
      throw const AccountValidationException('该请求已提交，请勿更改请求内容');
    }
    return entry;
  }

  void _checkWalletRevision(CardAccount card, int revision) {
    if (card.revision != revision)
      throw const AccountValidationException('余额或卡片已更新，请刷新后再试');
  }

  Future<CardAccount> issueCard(
    CardTier tier, {
    required String requestId,
    required String expectedUserId,
    PaymentMethod? method,
  }) => _changeWallet(
    userId: expectedUserId,
    kind: WalletEntryKind.issue,
    tier: tier,
    requestId: requestId,
    method: method,
  );
  Future<CardAccount> upgradeCard(
    CardTier tier, {
    required int expectedRevision,
    required String requestId,
    required String expectedUserId,
    PaymentMethod? method,
  }) => _changeWallet(
    userId: expectedUserId,
    kind: WalletEntryKind.upgrade,
    tier: tier,
    revision: expectedRevision,
    requestId: requestId,
    method: method,
  );
  Future<CardAccount> rechargeCard({
    required int cents,
    required PaymentMethod method,
    required int expectedRevision,
    required String requestId,
    required String expectedUserId,
  }) => _changeWallet(
    userId: expectedUserId,
    kind: WalletEntryKind.recharge,
    cents: cents,
    method: method,
    revision: expectedRevision,
    requestId: requestId,
  );
  Future<CardAccount> closeCard({
    required int expectedRevision,
    required String requestId,
    required String expectedUserId,
  }) => _changeWallet(
    userId: expectedUserId,
    kind: WalletEntryKind.close,
    revision: expectedRevision,
    requestId: requestId,
  );
  Future<CardAccount> adminSetCardTier({
    required String userId,
    required CardTier tier,
    required int expectedRevision,
    required String requestId,
    required String reason,
  }) => _changeWallet(
    userId: userId,
    kind: WalletEntryKind.upgrade,
    tier: tier,
    revision: expectedRevision,
    requestId: requestId,
    admin: true,
    reason: reason,
  );
  Future<CardAccount> adminAdjustBalance({
    required String userId,
    required int deltaCents,
    required int expectedRevision,
    required String requestId,
    required String reason,
  }) => _changeWallet(
    userId: userId,
    kind: WalletEntryKind.adminAdjustment,
    cents: deltaCents,
    revision: expectedRevision,
    requestId: requestId,
    admin: true,
    reason: reason,
  );
  Future<CardAccount> adminCloseCard({
    required String userId,
    required int expectedRevision,
    required String requestId,
    required String reason,
  }) => _changeWallet(
    userId: userId,
    kind: WalletEntryKind.close,
    revision: expectedRevision,
    requestId: requestId,
    admin: true,
    reason: reason,
  );

  Future<CardAccount> _changeWallet({
    required String userId,
    required WalletEntryKind kind,
    required String requestId,
    CardTier? tier,
    int cents = 0,
    PaymentMethod? method,
    int? revision,
    bool admin = false,
    String reason = '',
  }) => _serial(() async {
    if (admin) {
      _requireAdmin();
      if (reason.trim().isEmpty || reason.runes.length > 200)
        throw const AccountValidationException('请填写1～200字调整原因');
    } else if (_requireCustomer().id != userId) {
      throw const AccountValidationException('账号已切换，请重新打开页面');
    }
    final old = walletFor(userId);
    final fingerprint = jsonEncode([
      kind.name,
      tier?.name,
      cents,
      method?.name,
      admin,
      reason.trim(),
    ]);
    if (_replayed(userId, requestId, fingerprint) != null) return old;
    if (revision != null) _checkWalletRevision(old, revision);
    String? cardId = old.cardId;
    CardTier? nextTier = old.tier;
    var balance = old.balanceCents;
    var charged = 0;
    switch (kind) {
      case WalletEntryKind.issue:
        if (old.active) throw const AccountValidationException('已经办理充值卡，请选择升级');
        charged = membershipChargeCents(tier!);
        balance += charged;
        cardId = newLocalId('card');
        nextTier = tier;
      case WalletEntryKind.upgrade:
        if (!old.active && !admin)
          throw const AccountValidationException('请先办理充值卡');
        if (old.active && !admin && tier!.index <= old.tier!.index) {
          throw const AccountValidationException('只能升级更高等级，Plus为最高等级');
        }
        if (!admin) charged = membershipChargeCents(tier!, current: old.tier!);
        cardId ??= newLocalId('card');
        nextTier = tier;
      case WalletEntryKind.recharge:
        if (!old.active) throw const AccountValidationException('请先办理充值卡');
        if (cents <= 0 ||
            ![
              PaymentMethod.bankCard,
              PaymentMethod.wechat,
              PaymentMethod.alipay,
            ].contains(method)) {
          throw const AccountValidationException('充值金额或支付方式无效');
        }
        validateMoney(cents);
        balance += cents;
      case WalletEntryKind.adminAdjustment:
        if (!admin || !old.active || cents == 0)
          throw const AccountValidationException('请选择有效卡和非零调整金额');
        validateMoney(cents.abs());
        balance += cents;
      case WalletEntryKind.close:
        if (!old.active) throw const AccountValidationException('当前未办理充值卡');
        _ensureCardClosable(userId);
        balance = 0;
        cardId = null;
        nextTier = null;
      default:
        throw const AccountValidationException('不支持的卡操作');
    }
    if (charged > 0 &&
        !const [
          PaymentMethod.bankCard,
          PaymentMethod.wechat,
          PaymentMethod.alipay,
        ].contains(method)) {
      throw const AccountValidationException('请选择模拟支付方式并确认支付后办理或升级');
    }
    validateMoney(balance);
    final updated = old.changed(
      cardId: cardId,
      tier: nextTier,
      balanceCents: balance,
    );
    final entry = WalletEntry(
      id: newLocalId('transaction'),
      ownerId: userId,
      cardId: cardId ?? old.cardId!,
      actorId: _currentUser!.id,
      requestId: requestId,
      kind: kind,
      deltaCents: balance - old.balanceCents,
      balanceAfterCents: balance,
      chargedCents: charged,
      method: method,
      summary: '${kind.label}${nextTier == null ? '' : ' · ${nextTier.label}'}',
      reason: reason.trim(),
      at: _now(),
      fingerprint: fingerprint,
    );
    await _save(
      _accounts,
      _rememberedPhone,
      wallets: {..._wallets, userId: updated},
      walletEntries: [..._walletEntries, entry],
      action: admin ? '管理员${kind.label}' : kind.label,
      targetUserId: userId,
      detail:
          '${entry.summary}${charged > 0 ? ' · 模拟支付 ${money(charged)} · ${method!.label}' : ''} · 变动 ${money(entry.deltaCents)} · 余额 ${money(balance)}${reason.isEmpty ? '' : ' · $reason'}',
    );
    _notify();
    return updated;
  });

  void _ensureCardClosable(String ownerId) {
    if (_bookings.values.any(
      (b) => b.ownerId == ownerId && _unclosedCardBooking(b),
    )) {
      throw const AccountValidationException('仍有充值卡付款的未关闭预约，请先完成或取消预约再退卡');
    }
  }

  bool _unclosedCardBooking(Booking b) =>
      b.paymentMethod == PaymentMethod.rechargeCard &&
      b.netPaidCents > 0 &&
      b.canEdit;

  PaymentQuote quoteBookingPayment(String id, PaymentMethod method) {
    final booking = bookingById(id);
    if (booking.paymentMethod != null) {
      if (method != booking.paymentMethod)
        throw const BookingValidationException('补差额须使用原支付方式');
      return PaymentQuote(
        booking.amountCents,
        booking.payableCents,
        booking.lockedDiscountPercent,
      );
    }
    return quotePayment(
      booking.amountCents,
      method,
      method == PaymentMethod.rechargeCard
          ? walletFor(booking.ownerId).tier
          : null,
    );
  }

  Future<Booking> payBooking({
    required String id,
    required int expectedRevision,
    required PaymentMethod method,
    required String requestId,
    required String expectedActorId,
    int? expectedWalletRevision,
    String? managedStoreId,
  }) => _serial(() async {
    if (_currentUser?.id != expectedActorId)
      throw const AccountValidationException('账号已切换，请重新打开订单');
    final old = bookingById(id, managedStoreId: managedStoreId);
    final fingerprint = jsonEncode(['payment', id, method.name]);
    if (_replayed(old.ownerId, requestId, fingerprint) != null) return old;
    _checkRevision(old, expectedRevision);
    if (!old.canPay || !old.draft.appointment.isAfter(_now()))
      throw const BookingValidationException('预约无需支付、已关闭或到店时间已过');
    if (method == PaymentMethod.legacyMock &&
        old.paymentMethod != PaymentMethod.legacyMock) {
      throw const BookingValidationException('请选择有效支付方式');
    }
    final quote = quoteBookingPayment(id, method);
    final due = quote.payableCents - old.netPaidCents;
    if (due <= 0) throw const BookingValidationException('该预约无需再次支付');
    final wallet = walletFor(old.ownerId);
    var nextWallet = wallet;
    if (method == PaymentMethod.rechargeCard) {
      if (!wallet.active ||
          (old.paymentCardId != null && wallet.cardId != old.paymentCardId)) {
        throw const BookingValidationException('原充值卡已不可用');
      }
      if (expectedWalletRevision != null)
        _checkWalletRevision(wallet, expectedWalletRevision);
      if (wallet.balanceCents < due)
        throw const BookingValidationException('充值卡余额不足，请先充值');
      nextWallet = wallet.changed(
        cardId: wallet.cardId,
        tier: wallet.tier,
        balanceCents: wallet.balanceCents - due,
      );
    }
    final updated = old.copyWith(
      status: BookingStatus.paid,
      netPaidCents: quote.payableCents,
      payableCents: quote.payableCents,
      paymentMethod: method,
      paymentCardId: method == PaymentMethod.rechargeCard
          ? wallet.cardId
          : null,
      lockedDiscountPercent: quote.discountPercent,
      updatedAt: _now(),
    );
    final entry = WalletEntry(
      id: newLocalId('transaction'),
      ownerId: old.ownerId,
      cardId: wallet.cardId ?? 'external',
      actorId: _currentUser!.id,
      requestId: requestId,
      kind: WalletEntryKind.payment,
      deltaCents: -due,
      balanceAfterCents: nextWallet.balanceCents,
      method: method,
      bookingId: id,
      storeId: old.store.id,
      storeName: old.store.name,
      summary: '${old.store.name} · ${old.draft.service} · ${method.label}',
      at: _now(),
      fingerprint: fingerprint,
    );
    await _save(
      _accounts,
      _rememberedPhone,
      bookings: {..._bookings, id: updated},
      wallets: {..._wallets, old.ownerId: nextWallet},
      walletEntries: [..._walletEntries, entry],
      action: '模拟支付',
      targetUserId: old.ownerId,
      bookingId: id,
      detail:
          '${money(due)} · ${method.label} · 折扣${quote.discountPercent}%；无真实资金交易',
    );
    _notify();
    return updated;
  });

  // 退款、订单变化、余额和日志同一次保存，杜绝半完成退款。
  Future<void> _saveBookingRefund(
    Booking old,
    Booking updated,
    int refund,
    String action,
    String detail,
  ) async {
    final wallet = walletFor(old.ownerId);
    var nextWallet = wallet;
    final entries = <WalletEntry>[];
    if (refund > 0) {
      String refundRequest;
      do {
        refundRequest = newLocalId('internal-refund');
      } while (_walletEntries.any(
        (e) =>
            e.id == refundRequest ||
            (e.ownerId == old.ownerId && e.requestId == refundRequest),
      ));
      if (old.paymentMethod == PaymentMethod.rechargeCard) {
        if (!wallet.active || wallet.cardId != old.paymentCardId)
          throw const BookingValidationException('原充值卡不可用，无法退款');
        validateMoney(wallet.balanceCents + refund);
        nextWallet = wallet.changed(
          cardId: wallet.cardId,
          tier: wallet.tier,
          balanceCents: wallet.balanceCents + refund,
        );
      }
      entries.add(
        WalletEntry(
          id: newLocalId('transaction'),
          ownerId: old.ownerId,
          cardId: old.paymentCardId ?? 'external',
          actorId: _currentUser!.id,
          requestId: refundRequest,
          kind: WalletEntryKind.refund,
          deltaCents: refund,
          balanceAfterCents: nextWallet.balanceCents,
          method: old.paymentMethod ?? PaymentMethod.legacyMock,
          bookingId: old.id,
          storeId: old.store.id,
          storeName: old.store.name,
          summary: '${old.store.name} · $action',
          at: _now(),
          fingerprint: 'refund:${old.id}:${updated.revision}',
        ),
      );
    }
    await _save(
      _accounts,
      _rememberedPhone,
      bookings: {..._bookings, old.id: updated},
      wallets: refund > 0 ? {..._wallets, old.ownerId: nextWallet} : null,
      walletEntries: entries.isNotEmpty
          ? [..._walletEntries, ...entries]
          : null,
      action: action,
      targetUserId: old.ownerId,
      bookingId: old.id,
      detail: detail,
    );
  }

  // 串行提交：保存成功才更新界面，保存失败不留下半完成状态。
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _operation.then((_) {
      _requireReady();
      return action();
    });
    _operation = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> _save(
    Map<String, _DemoAccount> accounts,
    String? rememberedPhone, {
    Map<String, Booking>? bookings,
    Map<String, CardAccount>? wallets,
    List<WalletEntry>? walletEntries,
    Map<String, StoreSettings>? storeSettings,
    Set<String>? purgedRequests,
    List<AccountActivity>? retainedActivities,
    List<AccountActivity> addedActivities = const [],
    String? action,
    String? actorId,
    String? targetUserId,
    String detail = '',
    String? bookingId,
  }) async {
    final nextBookings = bookings ?? _bookings;
    final nextActivities = [
      ...(retainedActivities ?? _activities),
      ...addedActivities,
      if (action != null)
        AccountActivity(
          id: newLocalId('event'),
          actorId: actorId ?? _currentUser?.id ?? 'guest',
          targetUserId: targetUserId ?? _currentUser?.id ?? 'guest',
          action: action,
          detail: detail,
          bookingId: bookingId,
          at: _now(),
        ),
    ];
    final raw = jsonEncode({
      'version': 6,
      'storeSettings': [
        for (final s in demoStores)
          (storeSettings?[s.id] ??
                  _storeSettings[s.id] ??
                  StoreSettings.defaults(s))
              .toJson(),
      ],
      'legacyStoreNet': {
        for (final s in demoStores) s.id: _legacyStoreNet[s.id] ?? 0,
      },
      'wallets': (wallets ?? _wallets).values.map((w) => w.toJson()).toList(),
      'walletEntries': (walletEntries ?? _walletEntries)
          .map((e) => e.toJson())
          .toList(),
      'purgedRequests': (purgedRequests ?? _purgedRequests).toList(),
      'bookings': nextBookings.values
          .map((booking) => booking.toJson())
          .toList(),
      'activities': nextActivities.map((event) => event.toJson()).toList(),
      'rememberedPhone': rememberedPhone,
      'accounts': accounts.values
          .map(
            (account) => {
              'id': account.profile.id,
              'enabled': account.profile.enabled,
              'username': account.profile.username,
              'phone': account.profile.phone,
              'password': account.password,
              'avatar': account.profile.avatarBytes == null
                  ? null
                  : base64Encode(account.profile.avatarBytes!),
            },
          )
          .toList(),
    });
    try {
      // 该字符串只能交给加密存储，禁止写入日志或普通偏好设置。
      if (_writeState != null) await _writeState(raw);
    } catch (_) {
      throw const AccountValidationException('本地保存失败，请重试；本次修改未生效');
    }
    if (storeSettings != null) {
      _storeSettings
        ..clear()
        ..addAll(storeSettings);
    }
    if (bookings != null) {
      _bookings
        ..clear()
        ..addAll(bookings);
    }
    if (wallets != null) {
      _wallets
        ..clear()
        ..addAll(wallets);
    }
    if (walletEntries != null) {
      _walletEntries
        ..clear()
        ..addAll(walletEntries);
    }
    if (purgedRequests != null) {
      _purgedRequests
        ..clear()
        ..addAll(purgedRequests);
    }
    _activities
      ..clear()
      ..addAll(nextActivities);
  }

  Future<void> clearRememberedPhone() => _serial(() async {
    await _save(_accounts, null);
    _rememberedPhone = null;
    _notify();
  });

  Future<UserProfile> register({
    required String username,
    required String phone,
    required String password,
    bool rememberPhone = false,
  }) => _serial(() async {
    username = username.trim();
    phone = phone.trim();
    _requireValid(validateRegistrationPhone(phone));
    if (_accounts.containsKey(phone)) {
      throw const AccountValidationException('该手机号已被注册，请直接登录');
    }
    _requireValid(validateUsername(username));
    _requireValid(validatePassword(password));
    final profile = UserProfile(
      id: newLocalId('user'),
      username: username,
      phone: phone,
    );
    final next = Map<String, _DemoAccount>.from(_accounts);
    next[phone] = _DemoAccount(profile, password);
    final remembered = rememberPhone ? phone : null;
    await _save(
      next,
      remembered,
      action: '注册账号',
      actorId: profile.id,
      targetUserId: profile.id,
      detail: '$username · $phone',
    );
    _accounts[phone] = next[phone]!;
    _rememberedPhone = remembered;
    releaseStoreAuthorization();
    _sessionRevision++;
    _currentUser = profile;
    _notify();
    return profile;
  });

  Future<UserProfile> login({
    required String phone,
    required String password,
    bool rememberPhone = false,
  }) => _serial(() async {
    phone = phone.trim();
    _requireValid(validateLoginPhone(phone));
    UserProfile profile;
    if (phone == demoAdminPhone) {
      if (password != demoAdminPassword) {
        throw const AccountValidationException('手机号或密码不正确');
      }
      profile = UserProfile(
        username: '管理员',
        phone: demoAdminPhone,
        role: AccountRole.administrator,
      );
    } else {
      final account = _accounts[phone];
      if (account == null || account.password != password) {
        throw const AccountValidationException('手机号或密码不正确；首次使用请先注册');
      }
      profile = account.profile;
      if (!profile.enabled) throw const AccountValidationException('账号已被管理员停用');
    }
    // 不保存登录状态；此处仅更新下次登录表单需要填入的手机号。
    final remembered = rememberPhone ? phone : null;
    await _save(
      _accounts,
      remembered,
      action: '登录账号',
      actorId: profile.id,
      targetUserId: profile.id,
      detail: profile.username,
    );
    _rememberedPhone = remembered;
    releaseStoreAuthorization();
    _sessionRevision++;
    _currentUser = profile;
    _notify();
    return profile;
  });

  Future<UserProfile> updateProfile({
    required String username,
    required String phone,
    required Uint8List? avatarBytes,
  }) => _serial(() async {
    final oldProfile = _currentUser;
    if (oldProfile == null) {
      throw const AccountValidationException('请先登录');
    }
    if (isAdministrator) {
      throw const AccountValidationException('演示管理员账号不支持修改资料或绑定手机号');
    }
    username = username.trim();
    phone = phone.trim();
    _requireValid(validateUsername(username));
    _requireValid(validateRegistrationPhone(phone));
    if (phone != oldProfile.phone && _accounts.containsKey(phone)) {
      throw const AccountValidationException('该手机号已被其他账号使用');
    }
    if (avatarBytes != null && avatarBytes.length > 3 * 1024 * 1024) {
      throw const AccountValidationException('图片较大，请选择一张小于 3 MB 的头像');
    }
    final oldAccount = _accounts[oldProfile.phone]!;
    final updated = UserProfile(
      id: oldProfile.id,
      username: username,
      phone: phone,
      avatarBytes: avatarBytes,
    );
    final next = Map<String, _DemoAccount>.from(_accounts)
      ..remove(oldProfile.phone);
    next[phone] = _DemoAccount(updated, oldAccount.password);
    final remembered = _rememberedPhone == oldProfile.phone
        ? phone
        : _rememberedPhone;
    await _save(
      next,
      remembered,
      action: '修改用户资料',
      targetUserId: oldProfile.id,
      detail: '$username · $phone',
    );
    _passwordResetCodes.remove(oldProfile.phone);
    _passwordResetCodes.remove(phone);
    _resetRetryAt.remove(oldProfile.phone);
    _resetRetryAt.remove(phone);
    _accounts
      ..clear()
      ..addAll(next);
    _rememberedPhone = remembered;
    _currentUser = updated;
    _notify();
    return updated;
  });
  Duration passwordResetRetryAfter(String phone) {
    final retryAt = _resetRetryAt[phone.trim()];
    final now = _now();
    return retryAt != null && now.isBefore(retryAt)
        ? retryAt.difference(now)
        : Duration.zero;
  }

  bool hasActivePasswordResetCode(String phone) {
    final pending = _passwordResetCodes[phone.trim()];
    return pending != null && _now().isBefore(pending.challenge.expiresAt);
  }

  DemoPasswordResetCode requestPasswordResetCode({required String phone}) {
    _requireReady();
    phone = phone.trim();
    if (phone == demoAdminPhone) {
      throw const AccountValidationException('演示管理员账号不支持短信重置密码');
    }
    _requireValid(validatePhone(phone));
    if (!_accounts.containsKey(phone)) {
      throw const AccountValidationException('该手机号尚未注册，请先注册');
    }
    if (passwordResetRetryAfter(phone) > Duration.zero) {
      throw const AccountValidationException('请等待倒计时结束后再获取验证码');
    }

    final now = _now();
    var code = _generateResetCode();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw StateError('演示验证码生成器必须返回 6 位数字');
    }
    // 重新获取时确保新验证码不同，旧验证码立即失效。
    if (code == _passwordResetCodes[phone]?.challenge.code) {
      code = ((int.parse(code) + 1) % 1000000).toString().padLeft(6, '0');
    }
    final challenge = DemoPasswordResetCode(
      phone: phone,
      code: code,
      expiresAt: now.add(const Duration(minutes: 5)),
      resendAllowedAt: now.add(const Duration(seconds: 60)),
    );
    _passwordResetCodes[phone] = _PendingPasswordReset(challenge);
    _resetRetryAt[phone] = challenge.resendAllowedAt;
    return challenge;
  }

  Future<void> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) => _serial(() async {
    phone = phone.trim();
    if (phone == demoAdminPhone) {
      throw const AccountValidationException('演示管理员账号不支持短信重置密码');
    }
    code = code.trim();
    _requireValid(validatePhone(phone));
    _requireValid(validatePassword(newPassword));
    final account = _accounts[phone];
    if (account == null) {
      throw const AccountValidationException('该手机号尚未注册，请先注册');
    }
    final pending = _passwordResetCodes[phone];
    if (pending == null) {
      throw const AccountValidationException('请先获取演示验证码');
    }
    if (!_now().isBefore(pending.challenge.expiresAt)) {
      _passwordResetCodes.remove(phone);
      throw const AccountValidationException('验证码已过期，请重新获取');
    }
    if (code != pending.challenge.code) {
      pending.failedAttempts++;
      if (pending.failedAttempts >= 5) {
        _passwordResetCodes.remove(phone);
        throw const AccountValidationException('验证码错误次数过多，请重新获取');
      }
      throw AccountValidationException(
        '验证码不正确，还可尝试 ${5 - pending.failedAttempts} 次',
      );
    }
    if (account.password == newPassword) {
      throw const AccountValidationException('新密码不能与原密码相同');
    }

    final next = Map<String, _DemoAccount>.from(_accounts);
    next[phone] = _DemoAccount(account.profile, newPassword);
    await _save(
      next,
      _rememberedPhone,
      action: '重置密码',
      targetUserId: account.profile.id,
      detail: '已重置密码，不记录密码或验证码',
    );
    _accounts[phone] = next[phone]!;
    _passwordResetCodes.remove(phone);
    // 不自动登录；同一账号已有的本地登录状态也清除。
    if (_currentUser?.phone == phone) _currentUser = null;
    _notify();
  });

  void _checkRevision(Booking booking, int expectedRevision) {
    if (booking.revision != expectedRevision) {
      throw const BookingValidationException('预约已发生变化，请返回列表后重新打开');
    }
  }

  Future<Booking> createBooking({
    required StoreInfo store,
    required BookingDraft draft,
    required String requestId,
    int? expectedStoreRevision,
  }) => _serial(() async {
    final user = _requireCustomer();
    if (requestId.isEmpty) throw const BookingValidationException('提交标识无效');
    if (_purgedRequests.contains('${user.id}:$requestId')) {
      throw const BookingValidationException('原订单已被管理员彻底删除，请重新创建预约');
    }
    for (final existing in _bookings.values) {
      if (existing.ownerId == user.id && existing.requestId == requestId) {
        if (existing.hiddenFromCustomer) {
          throw const BookingValidationException('原预约已从列表删除，请重新创建预约');
        }
        if (existing.store.id != store.id || !existing.draft.sameAs(draft)) {
          throw const BookingValidationException('此预约已经提交，请到我的预约查看');
        }
        return existing;
      }
    }
    final settings = storeSettings(store.id);
    _checkStoreBooking(settings, expectedStoreRevision);
    draft.validate(_now(), settings: settings);
    final lines = quoteStoreSelections(
      settings,
      draft.service,
      draft.selections,
    );
    final currentStore = settings.info;
    final now = _now();
    final booking = Booking(
      id: newLocalId('booking'),
      requestId: requestId,
      ownerId: user.id,
      store: currentStore,
      draft: draft,
      status: BookingStatus.pendingPayment,
      amountCents: priceTotal(lines),
      priceLines: lines,
      netPaidCents: 0,
      mockRefundedCents: 0,
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    final next = {..._bookings, booking.id: booking};
    await _save(
      _accounts,
      _rememberedPhone,
      bookings: next,
      action: '提交预约',
      targetUserId: user.id,
      bookingId: booking.id,
      detail:
          '${currentStore.name} · ${draft.service} · 演示金额 ${money(booking.amountCents)}',
    );
    _notify();
    return booking;
  });

  Future<Booking> updateBooking({
    required String id,
    required int expectedRevision,
    required BookingDraft draft,
    int? expectedStoreRevision,
    String? managedStoreId,
  }) => _serial(() async {
    final old = bookingById(id);
    _checkManagedBooking(old, managedStoreId);
    _checkRevision(old, expectedRevision);
    if (!old.canEdit) throw const BookingValidationException('已取消或已完成的预约不能修改');
    if (draft.sameAs(old.draft)) return old;
    if (draft.service != old.draft.service) {
      throw const BookingValidationException('修改预约不能切换洗车与保养类型');
    }
    final settings = storeSettings(old.store.id);
    _checkStoreBooking(settings, expectedStoreRevision);
    draft.validate(
      _now(),
      settings: settings,
      requireFuture:
          draft.selections.isEmpty ||
          draft.selections[0].appointment != old.draft.appointment,
    );
    final lines = quoteStoreSelections(
      settings,
      draft.service,
      draft.selections,
      existing: old,
    );
    final amount = priceTotal(lines);
    final payable = (amount * old.lockedDiscountPercent + 50) ~/ 100;
    final paid = min(old.netPaidCents, payable);
    final refund = old.netPaidCents - paid;
    final updated = old.copyWith(
      draft: draft,
      amountCents: amount,
      payableCents: payable,
      priceLines: lines,
      netPaidCents: paid,
      mockRefundedCents: old.mockRefundedCents + refund,
      status: paid == payable
          ? BookingStatus.paid
          : BookingStatus.pendingPayment,
      updatedAt: _now(),
    );
    await _saveBookingRefund(
      old,
      updated,
      refund,
      '修改预约',
      '${old.store.name} · ${draft.selections[0].summary}${refund > 0 ? ' · 模拟退差额 ${money(refund)}' : ''}',
    );
    _notify();
    return updated;
  });

  Future<Booking> mockPayBooking(String id, int expectedRevision) async {
    final old = bookingById(id);
    _checkRevision(old, expectedRevision);
    return payBooking(
      id: id,
      expectedRevision: expectedRevision,
      method: old.paymentMethod ?? PaymentMethod.bankCard,
      requestId: 'compat-pay:$id:$expectedRevision',
      expectedActorId: _currentUser!.id,
    );
  }

  Future<Booking> cancelBooking(
    String id,
    int expectedRevision, {
    String? managedStoreId,
  }) => _serial(() async {
    final old = bookingById(id, managedStoreId: managedStoreId);
    _checkRevision(old, expectedRevision);
    if (!old.canEdit) throw const BookingValidationException('预约已关闭，不能重复取消');
    final updated = old.copyWith(
      status: BookingStatus.cancelled,
      netPaidCents: 0,
      mockRefundedCents: old.mockRefundedCents + old.netPaidCents,
      updatedAt: _now(),
    );
    await _saveBookingRefund(
      old,
      updated,
      old.netPaidCents,
      '取消预约',
      old.netPaidCents > 0
          ? '模拟退款 ${money(old.netPaidCents)}，无真实资金流动'
          : '取消未支付预约',
    );
    _notify();
    return updated;
  });

  Future<Booking> completeBooking(
    String id,
    int expectedRevision, {
    String? managedStoreId,
  }) => _serial(() async {
    _requireAdmin();
    final old = bookingById(id, managedStoreId: managedStoreId);
    _checkRevision(old, expectedRevision);
    if (old.status != BookingStatus.paid) {
      throw const BookingValidationException('仅已模拟支付的预约可标记完成');
    }
    final updated = old.copyWith(
      status: BookingStatus.completed,
      updatedAt: _now(),
    );
    await _save(
      _accounts,
      _rememberedPhone,
      bookings: {..._bookings, id: updated},
      action: '管理员模拟完成预约',
      targetUserId: old.ownerId,
      bookingId: id,
      detail: '仅演示状态，不代表真实服务已经完成',
    );
    _notify();
    return updated;
  });

  Future<void> hideBookingsFromCustomer(Map<String, int> expectedRevisions) =>
      _serial(() async {
        final user = _requireCustomer();
        if (expectedRevisions.isEmpty) {
          throw const BookingValidationException('请先勾选预约');
        }
        final selected = <Booking>[];
        for (final entry in expectedRevisions.entries) {
          final booking = bookingById(entry.key);
          _checkRevision(booking, entry.value);
          selected.add(booking);
        }
        final now = _now();
        final next = Map<String, Booking>.from(_bookings);
        for (final booking in selected) {
          next[booking.id] = booking.copyWith(
            customerDeletedAt: now,
            updatedAt: now,
          );
        }
        await _save(
          _accounts,
          _rememberedPhone,
          bookings: next,
          addedActivities: [
            for (final booking in selected)
              AccountActivity(
                id: newLocalId('event'),
                actorId: user.id,
                targetUserId: user.id,
                action: '用户删除预约（仅隐藏）',
                detail: '原状态：${booking.statusLabel}；不是取消预约，管理员仍可查看完整信息',
                bookingId: booking.id,
                at: now,
              ),
          ],
        );
        _notify();
      });

  Future<void> permanentlyDeleteBookings(
    Map<String, int> expectedRevisions, {
    String? managedStoreId,
  }) => _serial(() async {
    _requireAdmin();
    if (managedStoreId != null) requireStoreAuthorization(managedStoreId);
    if (expectedRevisions.isEmpty) {
      throw const BookingValidationException('请先勾选预约');
    }
    final selected = <Booking>[];
    for (final entry in expectedRevisions.entries) {
      final booking = bookingById(entry.key, managedStoreId: managedStoreId);
      _checkRevision(booking, entry.value);
      if (_unclosedCardBooking(booking))
        throw const BookingValidationException('充值卡付款预约需完成或取消后才能彻底删除');
      selected.add(booking);
    }
    final ids = expectedRevisions.keys.toSet();
    final next = Map<String, Booking>.from(_bookings)
      ..removeWhere((id, booking) => ids.contains(id));
    final logs = _activities
        .where((event) => !ids.contains(event.bookingId))
        .toList();
    await _save(
      _accounts,
      _rememberedPhone,
      bookings: next,
      retainedActivities: logs,
      purgedRequests: {
        ..._purgedRequests,
        for (final booking in selected)
          '${booking.ownerId}:${booking.requestId}',
      },
      addedActivities: [
        for (final booking in selected)
          AccountActivity(
            id: newLocalId('event'),
            actorId: _currentUser!.id,
            targetUserId: booking.ownerId,
            action: '管理员彻底删除预约',
            detail: '订单与关联明细日志已清除，仅保留此删除审计记录',
            bookingId: booking.id,
            at: _now(),
          ),
      ],
    );
    _notify();
  });

  Future<void> setUserEnabled(String userId, bool enabled) => _serial(() async {
    _requireAdmin();
    final old = userById(userId);
    if (old == null) throw const AccountValidationException('用户不存在');
    final account = _accounts[old.phone]!;
    final updated = UserProfile(
      id: old.id,
      username: old.username,
      phone: old.phone,
      avatarBytes: old.avatarBytes,
      enabled: enabled,
    );
    final next = {
      ..._accounts,
      old.phone: _DemoAccount(updated, account.password),
    };
    await _save(
      next,
      _rememberedPhone,
      action: enabled ? '启用用户' : '停用用户',
      targetUserId: old.id,
      detail: '${old.username} · 原有预约保留',
    );
    _accounts
      ..clear()
      ..addAll(next);
    _notify();
  });

  Future<void> adminUpdateUser({
    required String userId,
    required String username,
    required String phone,
  }) => _serial(() async {
    _requireAdmin();
    final old = userById(userId);
    if (old == null) throw const AccountValidationException('用户不存在');
    username = username.trim();
    phone = phone.trim();
    _requireValid(validateUsername(username));
    _requireValid(validateRegistrationPhone(phone));
    if (phone != old.phone && _accounts.containsKey(phone)) {
      throw const AccountValidationException('该手机号已被其他账号使用');
    }
    final account = _accounts[old.phone]!;
    final profile = UserProfile(
      id: old.id,
      username: username,
      phone: phone,
      enabled: old.enabled,
      avatarBytes: old.avatarBytes,
    );
    final next = Map<String, _DemoAccount>.from(_accounts)..remove(old.phone);
    next[phone] = _DemoAccount(profile, account.password);
    final remembered = _rememberedPhone == old.phone ? phone : _rememberedPhone;
    await _save(
      next,
      remembered,
      action: '管理员修改用户资料',
      targetUserId: old.id,
      detail: '$username · $phone',
    );
    _accounts
      ..clear()
      ..addAll(next);
    _rememberedPhone = remembered;
    _passwordResetCodes.remove(old.phone);
    _passwordResetCodes.remove(phone);
    _resetRetryAt.remove(old.phone);
    _resetRetryAt.remove(phone);
    _notify();
  });

  Future<void> logout() => _serial(() async {
    // 退出只清除内存会话，保留账号记录和勾选记住的手机号。
    if (_currentUser == null) return;
    await _save(
      _accounts,
      _rememberedPhone,
      action: '退出登录',
      detail: _currentUser!.username,
    );
    releaseStoreAuthorization();
    _sessionRevision++;
    _currentUser = null;
    _notify();
  });
}
