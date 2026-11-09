import 'dart:async';
import 'package:flutter/material.dart';
import '../models/store_info.dart';
import '../services/store_location_controller.dart';
import '../widgets/app_notice.dart';
import '../models/demo_account_store.dart';
import 'booking_editor_page.dart';
import 'admin_store_page.dart';
import '../widgets/store_image.dart';
import '../widgets/store_status_badge.dart';

// 主菜单也使用它，门店页被下一页面覆盖时暂停定位。
final storeRouteObserver = RouteObserver<ModalRoute<void>>();

class StoreSelectionPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String service;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  final Duration scrollDuration;
  const StoreSelectionPage({
    super.key,
    required this.accountStore,
    required this.service,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
    required this.scrollDuration,
  });
  @override
  State<StoreSelectionPage> createState() => _StoreSelectionPageState();
}

class _StoreSelectionPageState extends State<StoreSelectionPage>
    with WidgetsBindingObserver, RouteAware {
  final _location = StoreLocationController();
  final _keys = List.generate(demoStores.length, (_) => GlobalKey());
  PageController? _wheel;
  double _fraction = 0;
  double _page = 0;
  bool _opening = false;
  bool _foreground = true;
  bool _covered = false;
  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.accountStore.addListener(_refreshStores);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTracking();
    });
  }

  void _refreshStores() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != _route) {
      storeRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) storeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant StoreSelectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncTracking();
  }

  void _syncTracking() {
    _location.setTracking(widget.active && _foreground && !_covered);
  }

  @override
  void didPushNext() {
    _covered = true;
    _syncTracking();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncTracking();
  }

  @override
  void didPop() {
    _covered = true;
    _syncTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 权限弹窗的 inactive 不取消当前授权请求。
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    _syncTracking();
  }

  void _updateWheel() {
    if (mounted && _wheel?.hasClients == true) {
      setState(() => _page = _wheel!.page ?? 0);
    }
  }

  PageController _controllerFor(double fraction) {
    if (_wheel == null || (_fraction - fraction).abs() > 0.001) {
      final old = _wheel;
      old?.removeListener(_updateWheel);
      _fraction = fraction;
      _page = _page.round().clamp(0, demoStores.length - 1).toDouble();
      _wheel = PageController(
        initialPage: _page.toInt(),
        viewportFraction: fraction,
      )..addListener(_updateWheel);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _wheel!;
  }

  Future<void> _openStore(int index) async {
    if (_opening || !widget.active || _wheel?.hasClients != true) return;
    setState(() => _opening = true);
    try {
      if ((_page - index).abs() > 0.01) {
        await _wheel!.animateToPage(
          index,
          duration: widget.scrollDuration,
          curve: Curves.easeInOutCubic,
        );
        return;
      }
      final box = _keys[index].currentContext?.findRenderObject();
      if (box is! RenderBox || !mounted) return;
      final sourceRect = Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
      final store = widget.accountStore.stores[index];
      if (widget.service == '门店管理') {
        final accepted = await showStoreManagementCode(
          context,
          widget.accountStore,
          store.id,
          widget.enterDuration,
          widget.returnDuration,
        );
        if (!accepted || !mounted) return;
        widget.accountStore.requireStoreAuthorization(store.id);
      }
      // 截取数值而非伪造距离；详情里标注为进入时的定位快照。
      final entryDistance = distanceLabel(
        _location.hasFreshPosition ? _location.sample : null,
        store,
        DateTime.now(),
      );
      final route = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: widget.enterDuration,
        reverseTransitionDuration: widget.returnDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _StoreOpeningPage(
              accountStore: widget.accountStore,
              store: store,
              service: widget.service,
              animation: animation,
              sourceRect: sourceRect,
              distance: entryDistance,
              enterDuration: widget.enterDuration,
              returnDuration: widget.returnDuration,
              scrollDuration: widget.scrollDuration,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      );
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } catch (e) {
      if (mounted) AppNotice.show(context, e.toString());
    } finally {
      if (widget.service == '门店管理')
        widget.accountStore.releaseStoreAuthorization();
      if (mounted) setState(() => _opening = false);
    }
  }

  void _locate() {
    if (_location.state == StoreLocationState.disabled ||
        _location.state == StoreLocationState.deniedForever) {
      if (Theme.of(context).platform == TargetPlatform.android ||
          Theme.of(context).platform == TargetPlatform.iOS) {
        unawaited(_location.openSettings());
      } else {
        AppNotice.show(context, '请在系统或浏览器设置中开启位置权限');
      }
    } else {
      unawaited(_location.refresh(requestPermission: true));
    }
  }

  @override
  void dispose() {
    storeRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _wheel?.removeListener(_updateWheel);
    _wheel?.dispose();
    _location.dispose();
    widget.accountStore.removeListener(_refreshStores);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1020),
        image: DecorationImage(
          image: AssetImage('assets/images/store_background.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回主菜单',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.service} · 选择门店',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Text('成都', style: TextStyle(color: Color(0xFFC4B5FD))),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: _location,
              builder: (context, child) {
                final busy = _location.state == StoreLocationState.locating;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        size: 16,
                        color: Color(0xFFC4B5FD),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _location.statusText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB7AEC9),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: busy || !widget.active ? null : _locate,
                        child: Text(
                          _location.state == StoreLocationState.disabled ||
                                  _location.state ==
                                      StoreLocationState.deniedForever
                              ? '设置'
                              : _location.state == StoreLocationState.denied
                              ? '开启定位'
                              : '刷新',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final target =
                      (constraints.maxHeight * 0.30).clamp(190.0, 250.0) +
                      (textScale - 1).clamp(0.0, 3.0) * 130;
                  final fraction = ((target + 20) / constraints.maxHeight)
                      .clamp(0.30, 0.92)
                      .toDouble();
                  final controller = _controllerFor(fraction);
                  return ListenableBuilder(
                    listenable: _location,
                    builder: (context, child) => IgnorePointer(
                      ignoring: _opening || !widget.active,
                      child: PageView.builder(
                        key: ValueKey(fraction),
                        controller: controller,
                        scrollDirection: Axis.vertical,
                        itemCount: demoStores.length,
                        itemBuilder: (context, index) {
                          final relative = index - _page;
                          final distance = relative.abs().clamp(0.0, 1.0);
                          final selected = relative.abs() < 0.5;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateX(relative.clamp(-1.5, 1.5) * 0.55)
                              ..scaleByDouble(
                                1 - distance * 0.16,
                                1 - distance * 0.16,
                                1,
                                1,
                              ),
                            child: Opacity(
                              opacity: 1 - distance * 0.55,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 10,
                                ),
                                child: _StoreCard(
                                  key: _keys[index],
                                  store: widget.accountStore.stores[index],
                                  acceptingBookings: widget.accountStore
                                      .storeSettings(demoStores[index].id)
                                      .acceptingBookings,
                                  selected: selected,
                                  distance: distanceLabel(
                                    _location.hasFreshPosition
                                        ? _location.sample
                                        : null,
                                    demoStores[index],
                                    DateTime.now(),
                                  ),
                                  onTap: () => _openStore(index),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: Text(
                '${_page.round() + 1} / ${demoStores.length}  ·  演示门店 / 图片示意\n'
                '地址为真实地标参照；距离为到参照点的直线距离，非驾车路线。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: Color(0xFF9A92AA),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final bool acceptingBookings;
  final StoreInfo store;
  final String distance;
  final bool selected;
  final VoidCallback? onTap;
  final double expansion;
  final double centerProgress;
  const _StoreCard({
    super.key,
    this.acceptingBookings = true,
    required this.store,
    required this.distance,
    this.selected = true,
    this.onTap,
    this.expansion = 0,
    this.centerProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF251735),
      elevation: (selected ? 8 : 2) * (1 - expansion),
      shadowColor: const Color(0x664C2D73),
      borderRadius: BorderRadius.circular(22 * (1 - expansion)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StoreImage(store),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xB3000000),
                  Color(0x73000000),
                  Color(0x14000000),
                  Colors.transparent,
                ],
                stops: [0, 0.4, 0.75, 1],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, layout) => Align(
                    alignment: Alignment.lerp(
                      Alignment.centerLeft,
                      Alignment.center,
                      centerProgress,
                    )!,
                    child: SizedBox(
                      width:
                          layout.maxWidth * (1 - centerProgress) +
                          layout.maxWidth.clamp(0.0, 340.0) * centerProgress,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  store.name,
                                  style: TextStyle(
                                    fontSize: 18 + expansion * 6,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                StoreStatusBadge(
                                  acceptingBookings: acceptingBookings,
                                ),
                                const Text(
                                  '演示门店 · 图片示意',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFE0D3FF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                _line(
                                  Icons.location_on_outlined,
                                  store.address,
                                ),
                                const SizedBox(height: 5),
                                _line(Icons.near_me_outlined, distance),
                                const SizedBox(height: 5),
                                _line(
                                  Icons.phone_outlined,
                                  '${store.phone}（演示）',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Opacity(
                            opacity: 1 - expansion,
                            child: Icon(
                              selected
                                  ? Icons.chevron_right
                                  : Icons.circle_outlined,
                              color: Colors.white,
                              size: selected ? 24 : 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: Color(0xFFE0D3FF)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.35,
            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
          ),
        ),
      ),
    ],
  );
}

class _StoreOpeningPage extends StatelessWidget {
  final Duration scrollDuration;
  final DemoAccountStore accountStore;
  final StoreInfo store;
  final String service;
  final Animation<double> animation;
  final Rect sourceRect;
  final String distance;
  final Duration enterDuration;
  final Duration returnDuration;
  const _StoreOpeningPage({
    required this.scrollDuration,
    required this.accountStore,
    required this.store,
    required this.service,
    required this.animation,
    required this.sourceRect,
    required this.distance,
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
                  child: _StoreDetailPage(
                    scrollDuration: scrollDuration,
                    accountStore: accountStore,
                    store: store,
                    service: service,
                    distance: distance,
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
                    child: _StoreCard(
                      store: store,
                      acceptingBookings:accountStore.storeSettings(store.id).acceptingBookings,
                      distance: distance,
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

/// 门店当前资料；历史预约资料由订单快照单独展示。
class _StoreDetailPage extends StatefulWidget {
  final Duration scrollDuration;
  final DemoAccountStore accountStore;
  final StoreInfo store;
  final String service;
  final String distance;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  const _StoreDetailPage({
    required this.scrollDuration,
    required this.accountStore,
    required this.store,
    required this.service,
    required this.distance,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  State<_StoreDetailPage> createState() => _StoreDetailPageState();
}

class _StoreDetailPageState extends State<_StoreDetailPage> {
  DemoAccountStore get accountStore => widget.accountStore;
  StoreInfo get store => accountStore.storeSettings(widget.store.id).info;
  String get service => widget.service;
  String get distance => widget.distance;
  bool get active => widget.active;
  Duration get enterDuration => widget.enterDuration;
  Duration get returnDuration => widget.returnDuration;
  @override
  void initState() {
    super.initState();
    accountStore.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    accountStore.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => service == '门店管理'
      ? AdminStorePage(
          accountStore: accountStore,
          storeId: store.id,
          enterDuration: enterDuration,
          returnDuration: returnDuration,
          scrollDuration: widget.scrollDuration,
        )
      : service == '洗车' || service == '保养'
      ? BookingEditorPage(
          accountStore: accountStore,
          store: store,
          service: service,
          distance: distance,
          active: active,
          enterDuration: enterDuration,
          returnDuration: returnDuration,
        )
      : ColoredBox(
          color: const Color(0xFF0B1020),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回门店选择',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        service,
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
                  child: SizedBox(height: 200, child: StoreImage(store)),
                ),
                const SizedBox(height: 24),
                Text(
                  store.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                StoreStatusBadge(
                  acceptingBookings: accountStore
                      .storeSettings(store.id)
                      .acceptingBookings,
                ),
                Text(accountStore.storeSettings(store.id).description),
                Text('地址参照：${store.address}'),
                const SizedBox(height: 12),
                Text('进入时的位置快照：$distance'),
                const SizedBox(height: 12),
                Text('联系电话：${store.phone}（演示，不可拨打）'),
                const SizedBox(height: 24),
                const Text(
                  '门店、图片和电话仅用于界面演示。真实地标仅作地址与定位参照，'
                  '并不代表该处设有净车门店。',
                  style: TextStyle(color: Color(0xFFB7AEC9), height: 1.7),
                ),
                if (service == '联系我们') ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () =>
                        AppNotice.show(context, '这是演示号码，尚未配置真实门店电话'),
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text('联系门店'),
                  ),
                ],
              ],
            ),
          ),
        );
}
