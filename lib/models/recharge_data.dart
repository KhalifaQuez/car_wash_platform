enum CardTier { basic, pro, plus }

extension CardTierInfo on CardTier {
  String get label => ['Basic', 'Pro', 'Plus'][index];
  int get discountPercent => [95, 90, 85][index];
}

int membershipChargeCents(CardTier target, {CardTier? current}) {
  if (current == null) return target == CardTier.plus ? 50000 : 0;
  if (target.index <= current.index) {
    throw const FormatException('只能升级更高等级，Plus为最高等级');
  }
  const upgradePrices = [0, 10000, 30000];
  return upgradePrices[target.index] - upgradePrices[current.index];
}

enum PaymentMethod { bankCard, wechat, alipay, rechargeCard, legacyMock }

extension PaymentMethodInfo on PaymentMethod {
  String get label => ['银行卡支付', '微信支付', '支付宝', '充值卡支付', '旧模拟支付'][index];
}

enum WalletEntryKind {
  issue,
  upgrade,
  recharge,
  payment,
  refund,
  close,
  adminAdjustment,
}

extension WalletEntryInfo on WalletEntryKind {
  String get label =>
      ['办理', '升级/等级调整', '充值', '消费', '退款', '退卡清零', '管理员调整'][index];
}

const maxWalletCents = 900719925474;
void validateMoney(int cents) {
  if (cents < 0 || cents > maxWalletCents) {
    throw const FormatException('金额超出安全范围');
  }
}

int parseRechargeCents(String text) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text.trim());
  if (match == null) throw const FormatException('请输入正金额，最多两位小数');
  final whole = int.tryParse(match[1]!);
  if (whole == null || whole > maxWalletCents ~/ 100) {
    throw const FormatException('金额超出安全范围');
  }
  final cents = whole * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
  validateMoney(cents);
  if (cents == 0) throw const FormatException('金额必须大于零');
  return cents;
}

class PaymentQuote {
  final int originalCents;
  final int payableCents;
  final int discountPercent;
  int get discountCents => originalCents - payableCents;
  const PaymentQuote(
    this.originalCents,
    this.payableCents,
    this.discountPercent,
  );
}

PaymentQuote quotePayment(
  int originalCents,
  PaymentMethod method,
  CardTier? tier,
) {
  validateMoney(originalCents);
  if (method == PaymentMethod.rechargeCard && tier == null) {
    throw const FormatException('请先办理充值卡');
  }
  final percent = method == PaymentMethod.rechargeCard
      ? tier!.discountPercent
      : 100;
  return PaymentQuote(
    originalCents,
    (originalCents * percent + 50) ~/ 100,
    percent,
  );
}

class CardAccount {
  final String ownerId;
  final String? cardId;
  final CardTier? tier;
  final int balanceCents;
  final int revision;
  bool get active => cardId != null;
  const CardAccount({
    required this.ownerId,
    this.cardId,
    this.tier,
    this.balanceCents = 0,
    this.revision = 0,
  });
  CardAccount changed({
    required String? cardId,
    required CardTier? tier,
    required int balanceCents,
  }) => CardAccount(
    ownerId: ownerId,
    cardId: cardId,
    tier: tier,
    balanceCents: balanceCents,
    revision: revision + 1,
  );
  Map<String, dynamic> toJson() => {
    'ownerId': ownerId,
    'cardId': cardId,
    'tier': tier?.name,
    'balanceCents': balanceCents,
    'revision': revision,
  };
  factory CardAccount.fromJson(Map<String, dynamic> data) {
    if (data['ownerId'] is! String ||
        (data['ownerId'] as String).isEmpty ||
        data['balanceCents'] is! int ||
        data['revision'] is! int ||
        (data['revision'] as int) < 0 ||
        (data['cardId'] != null &&
            (data['cardId'] is! String ||
                (data['cardId'] as String).isEmpty))) {
      throw const FormatException('卡账户数据损坏');
    }
    final tier = data['tier'] == null
        ? null
        : CardTier.values.where((t) => t.name == data['tier']).firstOrNull;
    if ((data['cardId'] == null) != (data['tier'] == null) ||
        (data['tier'] != null && tier == null) ||
        (data['cardId'] == null && data['balanceCents'] != 0)) {
      throw const FormatException('卡账户状态损坏');
    }
    validateMoney(data['balanceCents'] as int);
    return CardAccount(
      ownerId: data['ownerId'] as String,
      cardId: data['cardId'] as String?,
      tier: tier,
      balanceCents: data['balanceCents'] as int,
      revision: data['revision'] as int,
    );
  }
}

class WalletEntry {
  final String id, ownerId, cardId, actorId, requestId, summary, reason;
  final WalletEntryKind kind;
  final int deltaCents, balanceAfterCents;
  final int chargedCents;
  final PaymentMethod? method;
  final String? bookingId;
  final String? storeId, storeName;
  final DateTime at;
  // 保存请求参数指纹，重试可验证参数一致且不重复记账。
  final String fingerprint;
  const WalletEntry({
    required this.id,
    required this.ownerId,
    required this.cardId,
    required this.actorId,
    required this.requestId,
    required this.kind,
    required this.deltaCents,
    required this.balanceAfterCents,
    this.chargedCents = 0,
    this.method,
    this.bookingId,
    this.storeId,
    this.storeName,
    required this.summary,
    this.reason = '',
    required this.at,
    required this.fingerprint,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'cardId': cardId,
    'actorId': actorId,
    'requestId': requestId,
    'kind': kind.name,
    'deltaCents': deltaCents,
    'balanceAfterCents': balanceAfterCents,
    'chargedCents': chargedCents,
    'method': method?.name,
    'bookingId': bookingId,
    'storeId': storeId,
    'storeName': storeName,
    'summary': summary,
    'reason': reason,
    'at': at.toIso8601String(),
    'fingerprint': fingerprint,
  };
  factory WalletEntry.fromJson(Map<String, dynamic> data) {
    if ((data['storeId'] == null) != (data['storeName'] == null) ||
        (data['storeId'] != null &&
            (data['storeId'] is! String ||
                data['storeName'] is! String ||
                (data['storeId'] as String).isEmpty ||
                (data['storeName'] as String).isEmpty)))
      throw const FormatException('交易门店归属损坏');
    for (final key in [
      'id',
      'ownerId',
      'cardId',
      'actorId',
      'requestId',
      'summary',
      'reason',
      'at',
      'fingerprint',
    ]) {
      if (data[key] is! String ||
          (key != 'reason' && (data[key] as String).isEmpty)) {
        throw const FormatException('交易流水损坏');
      }
    }
    final kind = WalletEntryKind.values
        .where((t) => t.name == data['kind'])
        .firstOrNull;
    final method = data['method'] == null
        ? null
        : PaymentMethod.values
              .where((t) => t.name == data['method'])
              .firstOrNull;
    if (kind == null ||
        (data['method'] != null && method == null) ||
        data['deltaCents'] is! int ||
        data['balanceAfterCents'] is! int ||
        (data['bookingId'] != null && data['bookingId'] is! String)) {
      throw const FormatException('交易流水损坏');
    }
    validateMoney((data['deltaCents'] as int).abs());
    validateMoney(data['balanceAfterCents'] as int);
    final charged = data.containsKey('chargedCents') ? data['chargedCents'] : 0;
    if (charged is! int) throw const FormatException('办卡收费记录损坏');
    validateMoney(charged);
    if (charged > 0 &&
        (!const [
              PaymentMethod.bankCard,
              PaymentMethod.wechat,
              PaymentMethod.alipay,
            ].contains(method) ||
            (kind == WalletEntryKind.issue
                ? charged != 50000 || data['deltaCents'] != charged
                : kind != WalletEntryKind.upgrade ||
                      !const [10000, 20000, 30000].contains(charged) ||
                      data['deltaCents'] != 0))) {
      throw const FormatException('办卡收费记录损坏');
    }
    return WalletEntry(
      id: data['id'] as String,
      ownerId: data['ownerId'] as String,
      cardId: data['cardId'] as String,
      actorId: data['actorId'] as String,
      requestId: data['requestId'] as String,
      kind: kind,
      deltaCents: data['deltaCents'] as int,
      balanceAfterCents: data['balanceAfterCents'] as int,
      chargedCents: charged,
      method: method,
      bookingId: data['bookingId'] as String?,
      storeId: data['storeId'] as String?,
      storeName: data['storeName'] as String?,
      summary: data['summary'] as String,
      reason: data['reason'] as String,
      at: DateTime.parse(data['at'] as String),
      fingerprint: data['fingerprint'] as String,
    );
  }
}
