import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/demo_account_store.dart';
import '../models/store_management_data.dart';
import '../widgets/store_image.dart';
import '../widgets/store_status_badge.dart';
import '../widgets/booking_dialogs.dart';
import '../widgets/app_notice.dart';
import 'admin_store_settings.dart';
import 'admin_store_services_page.dart';
import 'admin_store_revenue_page.dart';
import 'booking_list_page.dart';
import 'finance_route.dart';

Future<bool> showStoreManagementCode(
  BuildContext context,
  DemoAccountStore store,
  String id,
  Duration enter,
  Duration back,
) async {
  store.releaseStoreAuthorization();
  return await showBookingPopup<bool>(
        context,
        (_) => _StoreCodePopup(store: store, id: id),
        enter,
        back,
      ) ??
      false;
}

class _StoreCodePopup extends StatefulWidget {
  final DemoAccountStore store;
  final String id;
  const _StoreCodePopup({required this.store, required this.id});
  @override
  State<_StoreCodePopup> createState() => _StoreCodePopupState();
}

class _StoreCodePopupState extends State<_StoreCodePopup> {
  final input = TextEditingController();
  bool busy = false, closing = false;
  String? error;
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.store.sessionRevision;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> confirm() async {
    if (busy || closing) return;
    setState(() => busy = true);
    try {
      if (session != widget.store.sessionRevision)
        throw const AccountValidationException('账号已改变');
      await widget.store.authorizeStore(widget.id, input.text);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        setState(() {
          busy = false;
          closing = true;
        });
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
        AppNotice.show(context, e.toString());
      }
    } finally {
      if (mounted && !closing) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: BookingPopupSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '门店管理验证',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(widget.store.storeSettings(widget.id).info.name),
          TextField(
            key: const ValueKey('store-management-code'),
            controller: input,
            enabled: !busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '6位管理员代码',
              hintText: '字母与数字组合',
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Color(0xFFFFC7D4))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || closing
                      ? null
                      : () {
                          if (ModalRoute.of(context)?.isCurrent != true) return;
                          setState(() => closing = true);
                          Navigator.of(context).pop(false);
                        },
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy || closing ? null : confirm,
                  child: Text(busy ? '验证中…' : '验证并进入'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class StoreManagementView extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String storeId, title;
  final Widget Function(BuildContext, StoreSettings) builder;
  const StoreManagementView({
    super.key,
    required this.accountStore,
    required this.storeId,
    required this.title,
    required this.builder,
  });
  @override
  State<StoreManagementView> createState() => _StoreManagementViewState();
}

class _StoreManagementViewState extends State<StoreManagementView> {
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.accountStore.sessionRevision;
    widget.accountStore.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.accountStore.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    try {
      if (session != widget.accountStore.sessionRevision)
        throw const AccountValidationException('账号已改变，请重新验证门店');
      widget.accountStore.requireStoreAuthorization(widget.storeId);
      body = widget.builder(
        context,
        widget.accountStore.storeSettings(widget.storeId),
      );
    } catch (e) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$e，请返回'),
        ),
      );
    }
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
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: body,
      ),
    );
  }
}

class AdminStorePage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String storeId;
  final Duration enterDuration, returnDuration, scrollDuration;
  const AdminStorePage({
    super.key,
    required this.accountStore,
    required this.storeId,
    required this.enterDuration,
    required this.returnDuration,
    required this.scrollDuration,
  });
  @override
  State<AdminStorePage> createState() => _AdminStorePageState();
}

class _AdminStorePageState extends State<AdminStorePage> {
  bool busy = false;
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.accountStore.sessionRevision;
  }

  @override
  void dispose() {
    if (session == widget.accountStore.sessionRevision) {
      try {
        widget.accountStore.requireStoreAuthorization(widget.storeId);
        widget.accountStore.releaseStoreAuthorization();
      } catch (_) {
        /* another store or no grant */
      }
    }
    super.dispose();
  }

  Future<void> open(int index) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      widget.accountStore.requireStoreAuthorization(widget.storeId);
      final s = widget.accountStore,
          id = widget.storeId,
          e = widget.enterDuration,
          r = widget.returnDuration;
      if (index == 0) {
        await editStoreStatus(context, s, id, e, r);
      } else if (index == 3) {
        await openFinancePage<void>(
          context,
          AdminStoreServicesPage(
            accountStore: s,
            storeId: id,
            enterDuration: e,
            returnDuration: r,
          ),
          e,
          r,
        );
      } else if (index == 4) {
        await editStoreHours(context, s, id, e, r);
      } else if (index == 5) {
        await editStoreProfile(context, s, id, e, r);
      } else {
        await openFinancePage<void>(
          context,
          index == 1
              ? AdminStoreRevenuePage(
                  accountStore: s,
                  storeId: id,
                  enterDuration: e,
                  returnDuration: r,
                )
              : BookingListPage(
                  accountStore: s,
                  storeId: id,
                  active: true,
                  enterDuration: e,
                  returnDuration: r,
                  scrollDuration: widget.scrollDuration,
                ),
          e,
          r,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StoreManagementView(
    accountStore: widget.accountStore,
    storeId: widget.storeId,
    title: '门店管理',
    builder: (context, settings) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 2.8,
            child: StoreImage(settings.info),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          settings.info.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: StoreStatusBadge(
            acceptingBookings: settings.acceptingBookings,
          ),
        ),
        const SizedBox(height: 12),
        Text(settings.info.address),
        Text('联系电话：${settings.info.phone}（演示）'),
        Text(settings.description),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, c) {
            final columns =
                c.maxWidth < 330 ||
                    MediaQuery.textScalerOf(context).scale(14) > 22
                ? 1
                : 2;
            final side = (c.maxWidth - 14 * (columns - 1)) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < 6; i++)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : widget.enterDuration,
                    curve: Interval(i * .07, 1, curve: Curves.easeOutCubic),
                    builder: (context, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, 22 * (1 - v)),
                        child: Transform.scale(
                          scale: .92 + .08 * v,
                          child: child,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: FilledButton.tonal(
                        onPressed: busy ? null : () => open(i),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              [
                                Icons.power_settings_new,
                                Icons.trending_up,
                                Icons.event_note,
                                Icons.tune,
                                Icons.schedule,
                                Icons.storefront,
                              ][i],
                              size: 32,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              [
                                '营业状态',
                                '门店营业额',
                                '门店预约',
                                '服务项目',
                                '营业时间',
                                '门店资料',
                              ][i],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const Text(
          '本机演示管理 · 所有操作均记录日志，模拟收款不代表真实营业收入。',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    ),
  );
}
