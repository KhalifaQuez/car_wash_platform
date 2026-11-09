import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../models/service_option_data.dart';
import '../models/store_info.dart';
import '../models/service_pricing.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_dialogs.dart';
import '../widgets/store_service_options.dart';
import 'booking_payment_page.dart';
import 'finance_route.dart';
import '../models/store_management_data.dart';
import '../widgets/store_status_badge.dart';
import '../widgets/store_image.dart';

class BookingEditorPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final StoreInfo store;
  final String service;
  final String? bookingId;
  final String? managedStoreId;
  final String? distance;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  const BookingEditorPage({
    super.key,
    required this.accountStore,
    required this.store,
    required this.service,
    this.bookingId,
    this.managedStoreId,
    this.distance,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  State<BookingEditorPage> createState() => _BookingEditorPageState();
}

class _BookingEditorPageState extends State<BookingEditorPage> {
  final String _requestId = newLocalId('request');
  late List<ServiceOptionSelection?> _initial;
  late List<ServiceOptionSelection?> _selections;
  int? _revision;
  String? _submittedId;
  bool _busy = false;
  String? _loadError;
  late final int _session = widget.accountStore.sessionRevision;
  int? _shownStoreRevision;

  @override
  void initState() {
    super.initState();
    try {
      final booking = widget.bookingId == null
          ? null
          : widget.accountStore.bookingById(
              widget.bookingId!,
              managedStoreId: widget.managedStoreId,
            );
      _initial = booking == null
          ? List.filled(4, null)
          : List.of(booking.draft.selections);
      _revision = booking?.revision;
    } catch (error) {
      _initial = List.filled(4, null);
      _loadError = error.toString();
    }
    _selections = List.of(_initial);
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

  Booking? _current() {
    if (_session != widget.accountStore.sessionRevision)
      throw const AccountValidationException('账号已改变，请重新打开预约');
    final id = widget.bookingId ?? _submittedId;
    return id == null
        ? null
        : widget.accountStore.bookingById(
            id,
            managedStoreId: widget.managedStoreId,
          );
  }

  void _message(Object error) {
    if (mounted) AppNotice.show(context, error.toString());
  }

  Future<void> _submitOrUpdate() async {
    if (_busy || !widget.active || _submittedId != null) return;
    setState(() => _busy = true);
    try {
      final draft = BookingDraft(widget.service, _selections);
      final settings = widget.accountStore.storeSettings(widget.store.id);
      if (_shownStoreRevision != settings.revision)
        throw const BookingValidationException('门店配置已改变，请核对最新选项后重试');
      final existing = _current();
      draft.validate(
        DateTime.now(),
        settings: settings,
        requireFuture:
            existing == null ||
            draft.selections[0].appointment != existing.draft.appointment,
      );
      if (widget.bookingId == null) {
        final result = await widget.accountStore.createBooking(
          store: widget.store,
          draft: draft,
          requestId: _requestId,
          expectedStoreRevision: settings.revision,
        );
        if (mounted) {
          setState(() {
            _submittedId = result.id;
            _revision = result.revision;
          });
          AppNotice.show(context, '预约已保存，请在“我的预约”中查看和模拟支付');
        }
      } else {
        final old = widget.accountStore.bookingById(
          widget.bookingId!,
          managedStoreId: widget.managedStoreId,
        );
        if (draft.sameAs(old.draft)) {
          if (mounted) AppNotice.show(context, '服务未改变，保留订单原价格');
          return;
        }
        final nextAmount = priceTotal(
          quoteStoreSelections(
            settings,
            widget.service,
            _selections,
            existing: old,
          ),
        );
        if (nextAmount != old.amountCents) {
          final payable = (nextAmount * old.lockedDiscountPercent + 50) ~/ 100;
          final delta = payable - old.netPaidCents;
          final accepted = await confirmBookingAction(
            context,
            title: '确认修改演示预约',
            message: delta > 0
                ? '原项目 ${money(old.amountCents)} → 新项目 ${money(nextAmount)}。折后应付 ${money(payable)}，保存后需模拟支付差额 ${money(delta)}。'
                : '原项目 ${money(old.amountCents)} → 新项目 ${money(nextAmount)}。折后应付 ${money(payable)}，将模拟退差额 ${money(-delta)} 至原支付方式。',
            confirmLabel: '确认修改',
            enterDuration: widget.enterDuration,
            returnDuration: widget.returnDuration,
          );
          if (!accepted || !mounted) return;
        }
        _current();
        final updated = await widget.accountStore.updateBooking(
          id: widget.bookingId!,
          expectedRevision: _revision!,
          draft: draft,
          expectedStoreRevision: settings.revision,
          managedStoreId: widget.managedStoreId,
        );
        if (mounted) {
          setState(() => _revision = updated.revision);
          AppNotice.show(context, '预约修改已保存');
        }
      }
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    if (_busy || !widget.active) return;
    setState(() => _busy = true);
    try {
      final old = _current()!;
      final isPay = action == 'pay';
      final isComplete = action == 'complete';
      if ((isPay || isComplete) &&
          widget.bookingId != null &&
          !BookingDraft(widget.service, _selections).sameAs(old.draft)) {
        throw const BookingValidationException('请先确认修改已选服务，再执行此操作');
      }
      if (isPay) {
        await openFinancePage<bool>(
          context,
          BookingPaymentPage(
            managedStoreId: widget.managedStoreId,
            accountStore: widget.accountStore,
            bookingId: old.id,
            enterDuration: widget.enterDuration,
            returnDuration: widget.returnDuration,
          ),
          widget.enterDuration,
          widget.returnDuration,
        );
        if (mounted)
          setState(
            () => _revision = widget.accountStore.bookingById(old.id).revision,
          );
        return;
      }
      final accepted = await confirmBookingAction(
        context,
        title: isComplete ? '模拟完成预约' : '取消预约',
        message: isComplete
            ? '将此预约标记为已模拟完成，仅演示管理流程，不代表真实服务已完成。'
            : old.netPaidCents > 0
            ? '取消后将模拟退还 ${money(old.netPaidCents)}，没有真实资金流动。已取消预约不能再修改。'
            : '确定取消这个预约吗？取消后保留记录，但不能再修改或支付。',
        confirmLabel: isComplete ? '标记模拟完成' : '确认取消预约',
        enterDuration: widget.enterDuration,
        returnDuration: widget.returnDuration,
      );
      if (!accepted || !mounted) return;
      _current();
      final updated = isComplete
          ? await widget.accountStore.completeBooking(
              old.id,
              old.revision,
              managedStoreId: widget.managedStoreId,
            )
          : await widget.accountStore.cancelBooking(
              old.id,
              old.revision,
              managedStoreId: widget.managedStoreId,
            );
      if (mounted) {
        setState(() => _revision = updated.revision);
        AppNotice.show(context, isComplete ? '已标记模拟完成' : '预约已取消');
      }
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Booking? booking;
    String? error = _loadError;
    try {
      booking = _current();
    } catch (caught) {
      error = caught.toString();
    }
    final user = widget.accountStore.currentUser;
    final denied =
        user == null || (!widget.accountStore.isAdministrator && !user.enabled);
    if (error != null || denied) {
      return ColoredBox(
        color: const Color(0xFF0B1020),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  BackButton(onPressed: () => Navigator.of(context).pop()),
                  const Text('预约信息'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error ?? '请先登录有效账号'),
              ),
            ],
          ),
        ),
      );
    }
    final settings = widget.accountStore.storeSettings(widget.store.id);
    _shownStoreRevision = settings.revision;
    final displayStore = booking?.store ?? settings.info;
    final editable =
        settings.acceptingBookings &&
        !_busy &&
        _submittedId == null &&
        (booking?.canEdit ?? true);
    final specs = serviceOptionsFor(widget.service);
    List<ServicePriceLine>? previewLines;
    final unchanged =
        booking != null &&
        (BookingDraft(widget.service, _selections).sameAs(booking.draft) ||
            !booking.canEdit ||
            _submittedId != null);
    try {
      previewLines = unchanged
          ? booking.effectivePriceLines
          : quoteStoreSelections(
              settings,
              widget.service,
              _selections,
              existing: booking,
            );
    } catch (_) {
      /* 旧的、已下架选项须重新选择，不用零价冒充有效报价。 */
    }
    return ColoredBox(
      color: const Color(0xFF0B1020),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                BackButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    booking == null
                        ? widget.service
                        : '${widget.service} · 预约详情',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(height: 180, child: StoreImage(displayStore)),
            ),
            const SizedBox(height: 24),
            Text(
              displayStore.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            StoreStatusBadge(acceptingBookings: settings.acceptingBookings),
            if (!settings.acceptingBookings)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('门店已关门，暂停新增或修改预约；已有订单仍可查看、支付或取消。'),
              ),
            Text('地址参照：${displayStore.address}'),
            if (widget.distance != null) ...[
              const SizedBox(height: 10),
              Text('进入时的位置快照：${widget.distance}'),
            ],
            const SizedBox(height: 10),
            Text('联系电话：${displayStore.phone}（演示，不可拨打）'),
            if (booking == null) Text(settings.description),
            if (booking != null) ...[
              const SizedBox(height: 16),
              Text(
                '预约状态：${booking.statusLabel}',
                style: const TextStyle(color: Color(0xFFE0D3FF)),
              ),
              if (booking.hiddenFromCustomer)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '用户已从个人列表删除 · 删除时间 ${booking.customerDeletedAt}',
                    style: const TextStyle(
                      color: Color(0xFFFFC0D0),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '项目原价：${money(booking.amountCents)} · 折后应付：${money(booking.payableCents)} · 待模拟支付：${money(booking.balanceCents)}',
              ),
              if (booking.mockRefundedCents > 0)
                Text('累计模拟退款：${money(booking.mockRefundedCents)}'),
              const SizedBox(height: 8),
              SelectableText(
                '预约编号：${booking.id}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFBBAACD)),
              ),
              if (widget.accountStore.isAdministrator) ...[
                const SizedBox(height: 8),
                Text(
                  '预约用户：${widget.accountStore.userById(booking.ownerId)?.username ?? '用户'} · '
                  '${widget.accountStore.userById(booking.ownerId)?.phone ?? ''}',
                ),
              ],
              if (booking.canPay) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy || !widget.active ? null : () => _act('pay'),
                  child: Text('模拟支付预约订单 · ${money(booking.balanceCents)}'),
                ),
              ],
              if (widget.accountStore.isAdministrator &&
                  booking.status == BookingStatus.paid) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _busy || !widget.active
                      ? null
                      : () => _act('complete'),
                  child: const Text('标记模拟完成'),
                ),
              ],
            ],
            const SizedBox(height: 26),
            StoreServiceOptions(
              settings: settings,
              existing: booking,
              key: ValueKey(
                '${widget.bookingId ?? _requestId}:${booking != null && !booking.canEdit ? booking.revision : 'editing'}',
              ),
              service: widget.service,
              active: widget.active,
              editable: editable,
              initialSelections: booking != null && !booking.canEdit
                  ? booking.draft.selections
                  : _initial,
              animateEntrance: booking?.canEdit ?? true,
              priceTexts: [
                for (var index = 0; index < 4; index++)
                  previewLines == null
                      ? '价格待确认'
                      : '演示 ${money(priceForSection(previewLines, index))}',
              ],
              onChanged: (values) =>
                  setState(() => _selections = List.of(values)),
              enterDuration: widget.enterDuration,
              returnDuration: widget.returnDuration,
            ),
            if (booking != null && !editable && !_busy) ...[
              const SizedBox(height: 18),
              for (var index = 0; index < 4; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${specs[index].title}：${booking.draft.selections[index].summary}',
                  ),
                ),
            ],
            const SizedBox(height: 20),
            _PriceBreakdown(
              lines: previewLines,
              title: unchanged
                  ? '已保存订单价格'
                  : booking == null
                  ? '当前选择价格'
                  : '新报价（确认修改后生效）',
            ),
            const SizedBox(height: 16),
            Text(
              '门店、套餐、金额与时段均为演示数据。本机保存后管理员可查看；未接服务器与真实支付。'
              '\n套餐按演示基础价计费，用品及额外需求逐项相加；预约时间、文字备注不收费。',
              style: const TextStyle(
                color: Color(0xFFBBAACD),
                height: 1.6,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            if (booking == null)
              FilledButton(
                onPressed:
                    _busy || !widget.active || !settings.acceptingBookings
                    ? null
                    : _submitOrUpdate,
                child: Text(_busy ? '正在保存…' : '提交预约'),
              )
            else if (booking.canEdit) ...[
              if (_submittedId == null)
                FilledButton(
                  onPressed:
                      _busy || !widget.active || !settings.acceptingBookings
                      ? null
                      : _submitOrUpdate,
                  child: Text(_busy ? '正在保存…' : '确认修改'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy || !widget.active
                    ? null
                    : () => _act('cancel'),
                child: const Text('取消预约'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  final List<ServicePriceLine>? lines;
  final String title;
  const _PriceBreakdown({required this.lines, required this.title});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF281B37),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x445E477D)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (lines == null)
          const Text('部分项目价格未配置，请重新选择。')
        else ...[
          if (lines!.isEmpty)
            const Text(
              '选择项目后自动显示价格',
              style: TextStyle(color: Color(0xFFD2C4E3)),
            ),
          for (final line in lines!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(line.label)),
                  const SizedBox(width: 10),
                  Text(money(line.cents)),
                ],
              ),
            ),
          const Divider(color: Color(0xFF58416E)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '演示合计',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                money(priceTotal(lines!)),
                key: const ValueKey('booking-live-total'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE4D3FF),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
