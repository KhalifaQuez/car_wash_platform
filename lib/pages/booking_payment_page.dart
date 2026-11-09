import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../models/recharge_data.dart';
import '../widgets/app_notice.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/store_image.dart';

class BookingPaymentPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String bookingId;
  final String? managedStoreId;
  final Duration enterDuration, returnDuration;
  const BookingPaymentPage({
    super.key,
    required this.accountStore,
    required this.bookingId,
    this.managedStoreId,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  State<BookingPaymentPage> createState() => _BookingPaymentPageState();
}

class _BookingPaymentPageState extends State<BookingPaymentPage> {
  late final String _actorId;
  late final int _session = widget.accountStore.sessionRevision;
  PaymentMethod? _method;
  String _request = newLocalId('payment');
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _actorId = widget.accountStore.currentUser?.id ?? '';
    try {
      _method = widget.accountStore
          .bookingById(widget.bookingId, managedStoreId: widget.managedStoreId)
          .paymentMethod;
    } on AccountValidationException {
      /* build 显示权限变化提示。 */
    } on BookingValidationException {
      /* build 显示订单已不存在提示。 */
    }
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

  Future<void> _pay(Booking booking, CardAccount wallet) async {
    if (_busy || _method == null) return;
    setState(() => _busy = true);
    try {
      if (_session != widget.accountStore.sessionRevision)
        throw const AccountValidationException('账号已改变，请重新打开');
      await widget.accountStore.payBooking(
        managedStoreId: widget.managedStoreId,
        id: booking.id,
        expectedRevision: booking.revision,
        method: _method!,
        requestId: _request,
        expectedActorId: _actorId,
        expectedWalletRevision: _method == PaymentMethod.rechargeCard
            ? wallet.revision
            : null,
      );
      if (mounted) {
        AppNotice.show(context, '模拟支付成功');
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted)
        AppNotice.show(
          context,
          error is FormatException
              ? error.message.toString()
              : error.toString(),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Booking booking;
    CardAccount wallet;
    try {
      if (_session != widget.accountStore.sessionRevision ||
          widget.accountStore.currentUser?.id != _actorId)
        throw const AccountValidationException('账号已切换');
      booking = widget.accountStore.bookingById(
        widget.bookingId,
        managedStoreId: widget.managedStoreId,
      );
      wallet = widget.accountStore.walletFor(booking.ownerId);
    } catch (error) {
      return Scaffold(
        appBar: AppBar(title: const Text('预约支付')),
        body: Center(child: Text('$error，请返回')),
      );
    }
    PaymentQuote? quote;
    String? quoteError;
    if (_method != null) {
      try {
        quote = widget.accountStore.quoteBookingPayment(booking.id, _method!);
      } catch (error) {
        quoteError = error is FormatException
            ? error.message.toString()
            : error.toString();
      }
    }
    final due = quote == null
        ? booking.balanceCents
        : quote.payableCents - booking.netPaidCents;
    final sufficient =
        _method != PaymentMethod.rechargeCard ||
        wallet.active && wallet.balanceCents >= due;
    return PopScope(
      canPop: !_busy,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/store_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('预约支付'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: 2.8,
                  child: StoreImage(booking.store),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                booking.store.name,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(booking.store.address),
              Text('联系电话：${booking.store.phone}（演示）'),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x806B588E), Color(0xB3322949)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          color: Color(0xFFF5F0FF),
                          height: 1.6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${booking.draft.service} · ${booking.draft.appointment.toString().split('.').first}',
                            ),
                            for (
                              var i = 1;
                              i < booking.draft.selections.length;
                              i++
                            )
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  booking.draft.selections[i].summary,
                                ),
                              ),
                            const SizedBox(height: 20),
                            Text('项目原价：${money(booking.amountCents)}'),
                            Text(
                              '优惠：${money(quote?.discountCents ?? (booking.amountCents - booking.payableCents))}',
                            ),
                            if (quote != null && quote.discountPercent != 100)
                              Text('充值卡折扣：${quote.discountPercent / 10}折'),
                            Text(
                              '应付：${money(quote?.payableCents ?? booking.payableCents)} · 已付：${money(booking.netPaidCents)}',
                            ),
                            Text(
                              '本次待支付：${money(due)}',
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (booking.paymentMethod != null) const Text('补差额沿用原支付方式与原折扣。'),
              PaymentMethodSelector(
                methods: booking.paymentMethod == null
                    ? const [
                        PaymentMethod.bankCard,
                        PaymentMethod.wechat,
                        PaymentMethod.alipay,
                        PaymentMethod.rechargeCard,
                      ]
                    : [booking.paymentMethod!],
                selected: _method,
                enabled: !_busy,
                onChanged: (method) => setState(() {
                  _method = method;
                  _request = newLocalId('payment');
                }),
              ),
              Text(
                wallet.active
                    ? '${wallet.tier!.label}充值卡余额：${money(wallet.balanceCents)}'
                    : '尚未办理充值卡，可先到充值模块办理。',
              ),
              if (quoteError != null)
                Text(
                  quoteError,
                  style: const TextStyle(color: Color(0xFFFFC7D4)),
                ),
              if (!sufficient && quoteError == null)
                const Text(
                  '充值卡余额不足，请先充值或选择其它方式。',
                  style: TextStyle(color: Color(0xFFFFC7D4)),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    _busy ||
                        _method == null ||
                        quoteError != null ||
                        !sufficient ||
                        !booking.canPay
                    ? null
                    : () => _pay(booking, wallet),
                child: Text(_busy ? '处理中…' : '确认支付'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              const SizedBox(height: 20),
              const Text(
                '模拟付款。充值卡仅扣演示余额，其它方式不产生真实交易。',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
