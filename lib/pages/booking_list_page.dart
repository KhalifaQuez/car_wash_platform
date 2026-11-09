import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_wheel.dart';
import '../widgets/booking_dialogs.dart';
import 'booking_editor_page.dart';

class BookingListPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String? ownerId;
  final String? storeId;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  final Duration scrollDuration;
  const BookingListPage({
    super.key,
    required this.accountStore,
    this.ownerId,
    this.storeId,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
    required this.scrollDuration,
  });
  @override
  State<BookingListPage> createState() => _BookingListPageState();
}

class _BookingListPageState extends State<BookingListPage> {
  late final int _session;
  void _requireSession() {
    if (_session != widget.accountStore.sessionRevision)
      throw const AccountValidationException('账号已改变，请重新打开预约');
  }

  BookingStatus? _filter;
  bool _opening = false;
  bool _selecting = false;
  bool _hiddenOnly = false;
  final Map<String, int> _selected = {};
  @override
  void initState() {
    super.initState();
    _session = widget.accountStore.sessionRevision;
    widget.accountStore.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    try {
      final ids = widget.accountStore
          .visibleBookings(
            ownerId: widget.ownerId,
            managedStoreId: widget.storeId,
          )
          .map((booking) => booking.id)
          .toSet();
      _selected.removeWhere((id, revision) => !ids.contains(id));
    } catch (_) {
      _selected.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.accountStore.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _open(Booking booking, Rect sourceRect) async {
    if (_opening || !widget.active || _selecting) return;
    setState(() => _opening = true);
    try {
      _requireSession();
      final current = widget.accountStore.bookingById(
        booking.id,
        managedStoreId: widget.storeId,
      );
      final route = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: widget.enterDuration,
        reverseTransitionDuration: widget.returnDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _BookingOpeningPage(
              booking: current,
              accountStore: widget.accountStore,
              managedStoreId: widget.storeId,
              animation: animation,
              sourceRect: sourceRect,
              enterDuration: widget.enterDuration,
              returnDuration: widget.returnDuration,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      );
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } catch (error) {
      if (mounted) AppNotice.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _toggle(Booking booking) {
    if (_opening || !widget.active || !_selecting) return;
    setState(() {
      if (_selected.containsKey(booking.id)) {
        _selected.remove(booking.id);
      } else {
        _selected[booking.id] = booking.revision;
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_opening || !widget.active || _selected.isEmpty) return;
    final snapshot = Map<String, int>.from(_selected);
    final admin = widget.accountStore.isAdministrator;
    setState(() => _opening = true);
    try {
      final approved = await confirmBookingAction(
        context,
        title: admin
            ? '彻底删除 ${snapshot.length} 条预约'
            : '删除 ${snapshot.length} 条预约',
        message: admin
            ? '将永久清除勾选的订单及关联明细日志，用户和管理员都不能再查看，无法从 App 恢复。'
                  '此操作不等于取消或退款，不会产生真实资金流动。仅保留最小删除审计与防重复提交标识。'
            : '只从你的“我的预约”列表隐藏，管理员仍可查看完整服务、价格和订单状态。'
                  '这不是取消预约：未取消的预约仍保留原状态，也不会自动退款。',
        confirmLabel: admin ? '确认彻底删除（不可恢复）' : '确认从我的列表删除',
        enterDuration: widget.enterDuration,
        returnDuration: widget.returnDuration,
      );
      if (!approved || !mounted) return;
      _requireSession();
      if (admin) {
        await widget.accountStore.permanentlyDeleteBookings(
          snapshot,
          managedStoreId: widget.storeId,
        );
      } else {
        await widget.accountStore.hideBookingsFromCustomer(snapshot);
      }
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
        AppNotice.show(
          context,
          admin ? '已彻底删除 ${snapshot.length} 条预约，无法恢复' : '已从个人列表删除，管理员仍保留订单记录',
        );
      }
    } catch (error) {
      if (mounted) {
        if (error is BookingValidationException) setState(_selected.clear);
        AppNotice.show(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Booking> bookings;
    try {
      _requireSession();
      bookings = widget.accountStore.visibleBookings(
        ownerId: widget.ownerId,
        managedStoreId: widget.storeId,
      );
    } catch (error) {
      return ColoredBox(
        color: const Color(0xFF0B1020),
        child: SafeArea(
          child: Column(
            children: [
              const BackButton(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error.toString()),
              ),
            ],
          ),
        ),
      );
    }
    final admin = widget.accountStore.isAdministrator;
    final filtered = bookings
        .where(
          (booking) =>
              (_filter == null || booking.status == _filter) &&
              (!admin || !_hiddenOnly || booking.hiddenFromCustomer),
        )
        .toList();
    final owners = admin
        ? {
            for (final user in widget.accountStore.registeredUsers)
              user.id: '${user.username} · ${user.phone}',
          }
        : <String, String>{};
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0B1020),
          image: DecorationImage(
            image: AssetImage('assets/images/store_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Text(
                        admin ? '用户预约' : '我的预约',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${bookings.length} 条',
                      style: const TextStyle(color: Color(0xFFD2C4E3)),
                    ),
                    TextButton(
                      key: const ValueKey('booking-select-mode'),
                      onPressed: _opening || !widget.active
                          ? null
                          : () => setState(() {
                              _selecting = !_selecting;
                              _selected.clear();
                            }),
                      child: Text(_selecting ? '完成' : '勾选删除'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (admin)
                      FilterChip(
                        label: Text(
                          '用户已删除（${bookings.where((booking) => booking.hiddenFromCustomer).length}）',
                        ),
                        selected: _hiddenOnly,
                        onSelected: _opening || !widget.active
                            ? null
                            : (value) => setState(() {
                                _hiddenOnly = value;
                                _selected.clear();
                              }),
                      ),
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _filter == null,
                      onSelected: _opening || !widget.active
                          ? null
                          : (_) => setState(() {
                              _filter = null;
                              _selected.clear();
                            }),
                    ),
                    for (final status in BookingStatus.values)
                      ChoiceChip(
                        label: Text(switch (status) {
                          BookingStatus.pendingPayment => '待支付',
                          BookingStatus.paid => '已支付',
                          BookingStatus.cancelled => '已取消',
                          BookingStatus.completed => '已完成',
                        }),
                        selected: _filter == status,
                        onSelected: _opening || !widget.active
                            ? null
                            : (_) => setState(() {
                                _filter = status;
                                _selected.clear();
                              }),
                      ),
                  ],
                ),
              ),
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('已勾选 ${_selected.length} 条'),
                      TextButton(
                        onPressed: _opening || !widget.active
                            ? null
                            : () => setState(() {
                                final all =
                                    filtered.isNotEmpty &&
                                    filtered.every(
                                      (booking) =>
                                          _selected.containsKey(booking.id),
                                    );
                                _selected.clear();
                                if (!all) {
                                  _selected.addAll({
                                    for (final booking in filtered)
                                      booking.id: booking.revision,
                                  });
                                }
                              }),
                        child: const Text('全选 / 清空'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('booking-delete-selected'),
                        onPressed:
                            _opening || !widget.active || _selected.isEmpty
                            ? null
                            : _deleteSelected,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(admin ? '彻底删除选中' : '删除选中'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: BookingWheel(
                  bookings: filtered,
                  ownerLabels: owners,
                  active: widget.active,
                  busy: _opening,
                  scrollDuration: widget.scrollDuration,
                  onOpen: _open,
                  selectionMode: _selecting,
                  selectedIds: _selected.keys.toSet(),
                  onToggle: _toggle,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
                child: Text(
                  '本机演示预约 · 所有支付与退款均不涉及真实资金',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFFD2C4E3)),
                ),
              ),
            ],
          ), // Column
        ), // SafeArea
      ), // DecoratedBox
    ); // Scaffold
  }
}

class _BookingOpeningPage extends StatelessWidget {
  final String? managedStoreId;
  final Booking booking;
  final DemoAccountStore accountStore;
  final Animation<double> animation;
  final Rect sourceRect;
  final Duration enterDuration;
  final Duration returnDuration;
  const _BookingOpeningPage({
    this.managedStoreId,
    required this.booking,
    required this.accountStore,
    required this.animation,
    required this.sourceRect,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final expansion = const Interval(
            0,
            0.45,
            curve: Curves.easeInOutCubic,
          ).transform(animation.value);
          final center = const Interval(
            0.45,
            0.75,
            curve: Curves.easeInOutCubic,
          ).transform(animation.value);
          final fade = const Interval(
            0.75,
            1,
            curve: Curves.easeInOut,
          ).transform(animation.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: expansion,
                child: const ColoredBox(color: Color(0xFF0B1020)),
              ),
              IgnorePointer(
                ignoring: animation.value < 1,
                child: Opacity(
                  opacity: fade,
                  child: BookingEditorPage(
                    managedStoreId: managedStoreId,
                    accountStore: accountStore,
                    store: booking.store,
                    service: booking.draft.service,
                    bookingId: booking.id,
                    active: animation.value >= 1,
                    enterDuration: enterDuration,
                    returnDuration: returnDuration,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: Rect.lerp(
                  sourceRect,
                  Offset.zero & constraints.biggest,
                  expansion,
                )!,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1 - fade,
                    child: BookingCard(
                      booking: booking,
                      expansion: expansion,
                      centerProgress: center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
