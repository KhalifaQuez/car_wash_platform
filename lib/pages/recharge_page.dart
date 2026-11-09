import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../models/recharge_data.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_dialogs.dart';
import '../widgets/membership_card.dart';
import '../widgets/payment_method_selector.dart';
import 'finance_route.dart';
import 'wallet_history_page.dart';

class RechargePage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final bool active;
  final Duration enterDuration, returnDuration, scrollDuration;
  const RechargePage({
    super.key,
    required this.accountStore,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
    required this.scrollDuration,
  });
  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  late final String _ownerId;
  CardTier _selected = CardTier.basic;
  int? _cents;
  int? _preset;
  PaymentMethod? _method;
  String _request = newLocalId('topup');
  String _cardRequest = newLocalId('card');
  final _custom = TextEditingController();
  String? _amountError;
  bool _busy = false;
  bool get _allowed =>
      widget.active &&
      widget.accountStore.currentUser?.id == _ownerId &&
      widget.accountStore.currentUser?.enabled == true;
  @override
  void initState() {
    super.initState();
    _ownerId = widget.accountStore.currentUser?.id ?? '';
    if (widget.accountStore.currentUser?.role == AccountRole.customer &&
        widget.accountStore.currentUser?.enabled == true) {
      _selected =
          widget.accountStore.walletFor(_ownerId).tier ?? CardTier.basic;
    }
    widget.accountStore.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _custom.dispose();
    widget.accountStore.removeListener(_refresh);
    super.dispose();
  }

  void _message(Object error) => AppNotice.show(
    context,
    error is FormatException ? error.message.toString() : error.toString(),
  );
  Future<void> _run(Future<dynamic> Function() action, String message) async {
    if (_busy || !_allowed) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) AppNotice.show(context, message);
    } catch (error) {
      if (mounted) _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setAmount(int? value) {
    setState(() {
      _preset = value;
      _amountError = null;
      _cents = value == null ? null : value * 100;
      _request = newLocalId('topup');
    });
  }

  void _parseCustom(String text) {
    setState(() {
      _request = newLocalId('topup');
      try {
        _cents = parseRechargeCents(text);
        _amountError = null;
      } on FormatException catch (error) {
        _cents = null;
        _amountError = error.message.toString();
      }
    });
  }

  Future<void> _close(CardAccount card) async {
    if (_busy || !_allowed) return;
    final accepted = await confirmBookingAction(
      context,
      title: '确认退卡？',
      message:
          '当前余额 ${money(card.balanceCents)}。退卡不会退还卡内剩余金额，确认后余额将立即清零，建议消费完余额后再退卡。',
      confirmLabel: '确认退卡',
      cancelLabel: '暂不退卡',
      enterDuration: widget.enterDuration,
      returnDuration: widget.returnDuration,
    );
    if (!accepted || !mounted) return;
    await _run(
      () => widget.accountStore.closeCard(
        expectedRevision: card.revision,
        requestId: newLocalId('close'),
        expectedUserId: _ownerId,
      ),
      '退卡成功，余额已清零',
    );
    if (mounted && _allowed && !widget.accountStore.walletFor(_ownerId).active)
      setState(() {
        _cents = null;
        _method = null;
        _cardRequest = newLocalId('card');
      });
  }

  Future<void> _applyCard(CardAccount card) async {
    if (_busy || !_allowed) return;
    final target = _selected;
    if (card.active && target.index <= card.tier!.index) return;
    final request = _cardRequest;
    final charge = membershipChargeCents(target, current: card.tier);
    PaymentMethod? method;
    if (charge > 0) {
      setState(() => _busy = true);
      var closing = false;
      try {
        method = await showBookingPopup<PaymentMethod>(
          context,
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialog) => BookingPopupSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${card.active ? '升级' : '办理'} ${target.label}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('模拟支付：${money(charge)}'),
                  Text(
                    card.active
                        ? '升级费不计入卡内余额，原余额保持不变。'
                        : '办理成功后 ¥500.00 全额计入卡内余额。',
                  ),
                  PaymentMethodSelector(
                    methods: const [
                      PaymentMethod.bankCard,
                      PaymentMethod.wechat,
                      PaymentMethod.alipay,
                    ],
                    selected: method,
                    enabled: !closing,
                    onChanged: (value) => setDialog(() => method = value),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: closing
                              ? null
                              : () {
                                  if (ModalRoute.of(dialogContext)?.isCurrent !=
                                      true) {
                                    return;
                                  }
                                  setDialog(() => closing = true);
                                  Navigator.of(dialogContext).pop();
                                },
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: closing || method == null
                              ? null
                              : () {
                                  if (closing ||
                                      ModalRoute.of(dialogContext)?.isCurrent !=
                                          true) {
                                    return;
                                  }
                                  setDialog(() => closing = true);
                                  Navigator.of(dialogContext).pop(method);
                                },
                          child: const Text('确认模拟支付'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          widget.enterDuration,
          widget.returnDuration,
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (method == null || !mounted || !_allowed) return;
    }
    await _run(
      () async {
        if (card.active) {
          await widget.accountStore.upgradeCard(
            target,
            expectedRevision: card.revision,
            requestId: request,
            expectedUserId: _ownerId,
            method: method,
          );
        } else {
          await widget.accountStore.issueCard(
            target,
            requestId: request,
            expectedUserId: _ownerId,
            method: method,
          );
        }
        if (mounted) setState(() => _cardRequest = newLocalId('card'));
      },
      card.active
          ? '升级成功，升级费不计入余额'
          : target == CardTier.plus
          ? 'Plus办理成功，¥500.00已计入卡内余额'
          : '免费办理成功',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accountStore.currentUser?.id != _ownerId ||
        widget.accountStore.currentUser?.enabled != true ||
        widget.accountStore.currentUser?.role != AccountRole.customer)
      return const Scaffold(body: Center(child: Text('账号已切换，请返回')));
    final card = widget.accountStore.walletFor(_ownerId);
    final canUpgrade = card.active && _selected.index > card.tier!.index;
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/store_background.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text('充值'),
          leadingWidth: 132,
          leading: Row(
            children: [
              const BackButton(),
              TextButton(
                onPressed: _busy || !_allowed
                    ? null
                    : () => openFinancePage<void>(
                        context,
                        WalletHistoryPage(
                          accountStore: widget.accountStore,
                          userId: _ownerId,
                          enterDuration: widget.enterDuration,
                          returnDuration: widget.returnDuration,
                        ),
                        widget.enterDuration,
                        widget.returnDuration,
                      ),
                child: const Text('订单'),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            MembershipCardWheel(
              selectedTier: _selected,
              account: card,
              duration: widget.scrollDuration,
              onSelected: (tier) {
                if (!_busy && tier != _selected) {
                  setState(() {
                    _selected = tier;
                    _cardRequest = newLocalId('card');
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            if (!card.active || canUpgrade) ...[
              Text(
                card.active
                    ? '升级费用：${money(membershipChargeCents(_selected, current: card.tier))} · 不计入卡内余额'
                    : _selected == CardTier.plus
                    ? '办理 Plus：¥500.00 · 办理款全额计入卡内余额'
                    : '${_selected.label} 免费办理',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: !_allowed || _busy ? null : () => _applyCard(card),
                child: Text(card.active ? '升级办理 ${_selected.label}' : '办理'),
              ),
            ],
            if (card.active) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${card.tier!.label} · 余额 ${money(card.balanceCents)}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: !_allowed || _busy ? null : () => _close(card),
                    child: const Text('退卡'),
                  ),
                ],
              ),
              if (_selected.index < card.tier!.index)
                const Text(
                  '已持有更高等级，无需办理此卡。',
                  style: TextStyle(color: Colors.white60),
                ),
              if (_selected == card.tier)
                Text(
                  card.tier == CardTier.plus
                      ? '已办理 · Plus为最高等级'
                      : '已办理 · 可滑动选择更高等级升级',
                  style: const TextStyle(color: Colors.white60),
                ),
              const SizedBox(height: 24),
              const Text('选择充值金额', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final value in [100, 500, 1000, 5000])
                    SizedBox(
                      width: 112,
                      child: FilledButton.tonal(
                        onPressed: _busy || !_allowed
                            ? null
                            : () => _setAmount(value),
                        child: Text('¥$value${_preset == value ? ' ✓' : ''}'),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: _busy || !_allowed
                        ? null
                        : () => _setAmount(null),
                    child: const Text('自定义充值金额'),
                  ),
                ],
              ),
              if (_preset == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _custom,
                  enabled: !_busy && _allowed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _parseCustom,
                  decoration: InputDecoration(
                    labelText: '自定义金额（元）',
                    errorText: _amountError,
                    hintText: '最多两位小数',
                  ),
                ),
              ],
              if (_cents != null) ...[
                const SizedBox(height: 22),
                Text('充值 ${money(_cents!)} · 选择模拟支付方式'),
                PaymentMethodSelector(
                  methods: const [
                    PaymentMethod.bankCard,
                    PaymentMethod.wechat,
                    PaymentMethod.alipay,
                  ],
                  selected: _method,
                  enabled: !_busy && _allowed,
                  onChanged: (m) => setState(() {
                    _method = m;
                    _request = newLocalId('topup');
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy || !_allowed || _method == null
                            ? null
                            : () => _run(() async {
                                await widget.accountStore.rechargeCard(
                                  cents: _cents!,
                                  method: _method!,
                                  expectedRevision: card.revision,
                                  requestId: _request,
                                  expectedUserId: _ownerId,
                                );
                                if (mounted)
                                  setState(() {
                                    _cents = null;
                                    _preset = null;
                                    _method = null;
                                    _custom.clear();
                                    _request = newLocalId('topup');
                                  });
                              }, '模拟充值成功'),
                        child: Text(_busy ? '处理中…' : '确认支付'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _cents = null;
                                _method = null;
                                _preset = null;
                                _custom.clear();
                              }),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 28),
            const Text(
              'Basic、Pro免费办理；Plus办理支付¥500并全额入卡。Basic升级Pro¥100、Pro升级Plus¥200、Basic升级Plus¥300，升级费不计入余额。全部为本机模拟支付；退卡后余额立即清零。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white60,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
