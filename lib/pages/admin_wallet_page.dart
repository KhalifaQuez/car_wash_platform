import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../models/recharge_data.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_dialogs.dart';
import '../widgets/membership_card.dart';
import 'finance_route.dart';
import 'wallet_history_page.dart';

class AdminWalletPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String userId;
  final Duration enterDuration, returnDuration;
  const AdminWalletPage({
    super.key,
    required this.accountStore,
    required this.userId,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  State<AdminWalletPage> createState() => _AdminWalletPageState();
}

class _AdminWalletPageState extends State<AdminWalletPage> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.accountStore.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.accountStore.removeListener(_refresh);
    super.dispose();
  }

  String _previewBalance(CardAccount card, String text, bool subtract) {
    try {
      final result =
          card.balanceCents + parseRechargeCents(text) * (subtract ? -1 : 1);
      validateMoney(result);
      return money(result);
    } on FormatException {
      return '请输入有效金额';
    }
  }

  Future<void> _edit(String action, CardAccount card) async {
    if (_busy || !widget.accountStore.isAdministrator) return;
    setState(() => _busy = true);
    final reason = TextEditingController();
    final amount = TextEditingController();
    var tier = card.tier ?? CardTier.basic;
    var subtract = false;
    String? error;
    var closing = false;
    final result =
        await showBookingPopup<({CardTier tier, int delta, String reason})>(
          context,
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialog) => BookingPopupSurface(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action == 'tier'
                          ? '办理或调整卡片等级'
                          : action == 'balance'
                          ? '调整演示余额'
                          : '确认退卡',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('当前余额：${money(card.balanceCents)}'),
                    if (action == 'tier')
                      Text('等级：${card.tier?.label ?? '未办理'} → ${tier.label}'),
                    if (action == 'close')
                      const Text(
                        '退卡不会退还卡内剩余金额，确认后余额将立即清零，建议消费完余额后再退卡。',
                        style: TextStyle(color: Color(0xFFFFC7D4), height: 1.6),
                      ),
                    if (action == 'tier')
                      DropdownButtonFormField<CardTier>(
                        initialValue: tier,
                        items: [
                          for (final t in CardTier.values)
                            DropdownMenuItem(value: t, child: Text(t.label)),
                        ],
                        onChanged: closing
                            ? null
                            : (t) {
                                if (t != null) setDialog(() => tier = t);
                              },
                      ),
                    if (action == 'balance') ...[
                      Wrap(
                        spacing: 10,
                        children: [
                          TextButton(
                            onPressed: () => setDialog(() => subtract = false),
                            child: Text('增加余额${!subtract ? ' ✓' : ''}'),
                          ),
                          TextButton(
                            onPressed: () => setDialog(() => subtract = true),
                            child: Text('减少余额${subtract ? ' ✓' : ''}'),
                          ),
                        ],
                      ),
                      TextField(
                        controller: amount,
                        enabled: !closing,
                        onChanged: (_) => setDialog(() => error = null),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '调整金额（元）'),
                      ),
                      Text(
                        '调整后余额：${_previewBalance(card, amount.text, subtract)}',
                      ),
                    ],
                    TextField(
                      controller: reason,
                      enabled: !closing,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: '管理原因（必填）'),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFFC7D4)),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: closing
                              ? null
                              : () {
                                  if (closing ||
                                      ModalRoute.of(dialogContext)?.isCurrent !=
                                          true)
                                    return;
                                  setDialog(() => closing = true);
                                  Navigator.of(dialogContext).pop();
                                },
                          child: Text(action == 'close' ? '暂不退卡' : '取消'),
                        ),
                        FilledButton(
                          onPressed: closing
                              ? null
                              : () {
                                  if (closing ||
                                      ModalRoute.of(dialogContext)?.isCurrent !=
                                          true)
                                    return;
                                  try {
                                    if (reason.text.trim().isEmpty)
                                      throw const FormatException('请填写管理原因');
                                    final delta = action == 'balance'
                                        ? parseRechargeCents(amount.text) *
                                              (subtract ? -1 : 1)
                                        : 0;
                                    if (card.balanceCents + delta < 0)
                                      throw const FormatException('调整后余额不能小于零');
                                    setDialog(() => closing = true);
                                    Navigator.of(dialogContext).pop((
                                      tier: tier,
                                      delta: delta,
                                      reason: reason.text.trim(),
                                    ));
                                  } on FormatException catch (e) {
                                    setDialog(
                                      () => error = e.message.toString(),
                                    );
                                  }
                                },
                          child: Text(action == 'close' ? '确认退卡' : '确认调整'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          widget.enterDuration,
          widget.returnDuration,
        );
    reason.dispose();
    amount.dispose();
    if (!mounted) return;
    if (result == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final request = newLocalId('admin-wallet');
      if (action == 'tier') {
        await widget.accountStore.adminSetCardTier(
          userId: widget.userId,
          tier: result.tier,
          expectedRevision: card.revision,
          requestId: request,
          reason: result.reason,
        );
      } else if (action == 'balance') {
        await widget.accountStore.adminAdjustBalance(
          userId: widget.userId,
          deltaCents: result.delta,
          expectedRevision: card.revision,
          requestId: request,
          reason: result.reason,
        );
      } else {
        await widget.accountStore.adminCloseCard(
          userId: widget.userId,
          expectedRevision: card.revision,
          requestId: request,
          reason: result.reason,
        );
      }
      if (mounted) AppNotice.show(context, '管理操作已保存并记录日志');
    } catch (e) {
      if (mounted) AppNotice.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.accountStore.isAdministrator)
      return const Scaffold(body: Center(child: Text('仅管理员可查看，请返回')));
    final card = widget.accountStore.walletFor(widget.userId);
    final user = widget.accountStore.userById(widget.userId);
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
          title: const Text('充值卡管理'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${user?.username ?? '用户'} · ${user?.phone ?? ''}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 24),
            if (card.active) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 20,
                    ),
                    child: MembershipCard(
                      tier: card.tier!,
                      selected: true,
                      account: card,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('尚未办理充值卡'),
              ),
            ],
            Text('当前等级：${card.tier?.label ?? '未办理'}'),
            Text(
              '演示余额：${money(card.balanceCents)}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => _edit('tier', card),
              child: const Text('办理或调整等级'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy || !card.active
                  ? null
                  : () => _edit('balance', card),
              child: const Text('调整余额'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy || !card.active
                  ? null
                  : () => _edit('close', card),
              child: const Text('退卡并清零'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => openFinancePage<void>(
                      context,
                      WalletHistoryPage(
                        accountStore: widget.accountStore,
                        userId: widget.userId,
                        enterDuration: widget.enterDuration,
                        returnDuration: widget.returnDuration,
                      ),
                      widget.enterDuration,
                      widget.returnDuration,
                    ),
              child: const Text('查看全部交易流水'),
            ),
            const SizedBox(height: 24),
            const Text(
              '调整需填写原因并生成新流水，历史充值和消费记录不能直接改写。全部为本机演示资金。',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
