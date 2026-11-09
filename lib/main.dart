import 'package:flutter/material.dart';
import 'widgets/wash_image_carousel.dart';
import 'widgets/module_image_carousel.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'widgets/account_actions.dart';
import 'widgets/app_notice.dart';
import 'widgets/app_background.dart';
import 'models/demo_account_store.dart';
import 'widgets/user_profile_header.dart';
import 'pages/profile_edit_page.dart';
import 'theme/app_theme.dart';
import 'services/account_storage.dart';
import 'pages/store_selection_page.dart';
import 'pages/booking_list_page.dart';
import 'pages/admin_users_page.dart';
import 'pages/recharge_page.dart';

// 全项目统一动画时长。
// 启动：文字 2.8 秒 → 背景渐显 1.2 秒 → 菜单展开 2 秒。
const introDuration = Duration(milliseconds: 6000);
const pageEnterDuration = Duration(milliseconds: 1200);
const pageReturnDuration = Duration(milliseconds: 1000);
const menuScrollDuration = Duration(milliseconds: 600);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CarWashApp());
}

class CarWashApp extends StatelessWidget {
  const CarWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '净车到家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      navigatorObservers: [storeRouteObserver],
      builder: (context, child) {
        return AppNoticeHost(
          enterDuration: pageEnterDuration,
          exitDuration: pageReturnDuration,
          child: AppBackground(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const AccountStartupPage(),
    );
  }
}

// 加载失败时允许重试，不降级为一个空账号库覆盖原数据。
class AccountStartupPage extends StatefulWidget {
  const AccountStartupPage({super.key});
  @override
  State<AccountStartupPage> createState() => _AccountStartupPageState();
}

class _AccountStartupPageState extends State<AccountStartupPage> {
  late Future<DemoAccountStore> _loading;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<DemoAccountStore> _load() async {
    final store = DemoAccountStore(
      readState: AccountStorage.read,
      writeState: AccountStorage.write,
    );
    await store.initialize();
    return store;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DemoAccountStore>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) return MainMenuPage(store: snapshot.data!);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '本地账号暂时无法读取，请重试。\n原有数据不会自动清空。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => setState(() => _loading = _load()),
                        child: const Text('重新读取'),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class MainMenuPage extends StatefulWidget {
  final DemoAccountStore? store;
  const MainMenuPage({super.key, this.store});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _sessionController;
  late final Animation<double> _sessionOpacity;
  late final Animation<Offset> _sessionOffset;
  late final Animation<double> _welcomeOpacity;
  late PageController _pageController;

  late final DemoAccountStore _accountStore;
  bool _showingAdmin = false;

  double _currentPage = 0;
  bool _openingModule = false;
  // 获取每张卡片的位置。
  final List<GlobalKey> _cardKeys = List.generate(5, (_) => GlobalKey());

  // 每个模块独立捕获当前轮播画面，展开时不会跳回第一张。
  final List<GlobalKey> _backgroundKeys = List.generate(5, (_) => GlobalKey());

  List<MenuItem> get _menuItems =>
      _accountStore.isAdministrator ? _adminMenuItems : _customerMenuItems;

  static const List<MenuItem> _adminMenuItems = [
    MenuItem(
      title: '门店管理',
      subtitle: '管理门店资料与服务项目',
      icon: Icons.storefront_outlined,
      colors: [Color(0xFF6C4599), Color(0xFF251735)],
      adminOnly: true,
      imageAssets: [
        'assets/images/store_manage_1.png',
        'assets/images/store_manage_2.png',
        'assets/images/store_manage_3.png',
        'assets/images/store_manage_4.png',
        'assets/images/store_manage_5.png',
      ],
    ),
    MenuItem(
      title: '用户管理',
      subtitle: '查看与管理用户信息',
      icon: Icons.manage_accounts_outlined,
      colors: [Color(0xFF8260AF), Color(0xFF322047)],
      adminOnly: true,
      imageAssets: [
        'assets/images/user_manage_1.png',
        'assets/images/user_manage_2.png',
        'assets/images/user_manage_3.png',
        'assets/images/user_manage_4.png',
        'assets/images/user_manage_5.png',
      ],
    ),
  ];

  static const List<MenuItem> _customerMenuItems = [
    MenuItem(
      title: '洗车',
      subtitle: '预约专业洗车服务',
      icon: Icons.local_car_wash_outlined,
      colors: [Color(0xFF1457B6), Color(0xFF193F77)],
    ),
    MenuItem(
      title: '保养',
      subtitle: '守护爱车每一次出行',
      icon: Icons.build_circle_outlined,
      colors: [Color(0xFF5145A6), Color(0xFF2B2354)],
      imageAssets: [
        'assets/images/care_1.JPG',
        'assets/images/care_2.JPG',
        'assets/images/care_3.JPG',
        'assets/images/care_4.JPG',
        'assets/images/care_5.JPG',
      ],
    ),
    MenuItem(
      title: '充值',
      subtitle: '会员储值，享受更多优惠',
      icon: Icons.account_balance_wallet_outlined,
      colors: [Color(0xFF4C2D73), Color(0xFF21152F)],
      imageAssets: [
        'assets/images/recharge_1.png',
        'assets/images/recharge_2.png',
        'assets/images/recharge_3.png',
        'assets/images/recharge_4.png',
        'assets/images/recharge_5.png',
      ],
    ),
    MenuItem(
      title: '联系我们',
      subtitle: '为您解答服务相关问题',
      icon: Icons.support_agent_outlined,
      colors: [Color(0xFF4C2D73), Color(0xFF21152F)],
      imageAssets: [
        'assets/images/contact_1.png',
        'assets/images/contact_2.png',
        'assets/images/contact_3.png',
        'assets/images/contact_4.png',
        'assets/images/contact_5.png',
      ],
    ),
    // 在 main.dart 的菜单列表中，替换原来的“我的预约”MenuItem。
    MenuItem(
      title: '我的预约',
      subtitle: '查看、修改与管理预约订单',
      icon: Icons.event_note_outlined,
      colors: [Color(0xFF77519B), Color(0xFF281B3B)],
      imageAssets: [
        'assets/images/booking_1.png',
        'assets/images/booking_2.png',
        'assets/images/booking_3.png',
        'assets/images/booking_4.png',
        'assets/images/booking_5.png',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _accountStore = widget.store ?? DemoAccountStore();
    _showingAdmin = _accountStore.isAdministrator;
    _accountStore.onChanged = _onAccountChanged;

    _pageController = PageController(viewportFraction: 0.30);
    _pageController.addListener(_updatePage);

    // 整段启动动画的时间。
    _introController = AnimationController(
      vsync: this,
      duration: introDuration,
    );
    _sessionController = AnimationController(
      vsync: this,
      value: 1,
      duration: pageEnterDuration,
      reverseDuration: pageReturnDuration,
    );
    _sessionOpacity = _sessionController.drive(
      CurveTween(curve: Curves.easeInOutCubic),
    );
    _sessionOffset = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(_sessionOpacity);

    // 文字：渐显 → 停留 → 渐隐。
    _welcomeOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 10),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50 / 3,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 160 / 3),
    ]).animate(_introController);

    _introController.forward();
  }

  void _updatePage() {
    final page = _pageController.page ?? 0;

    if (page != _currentPage) {
      setState(() {
        _currentPage = page;
      });
    }
  }

  // 将某段时间转换成 0～1 的动画进度。
  double _progress(double start, double end) {
    return ((_introController.value - start) / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<void> _onCardTap(int index) async {
    if (!_introController.isCompleted || _openingModule) {
      return;
    }

    // 未登录时，禁止打开任何模块。
    if (_accountStore.currentUser == null) {
      AppNotice.show(context, '请登录或注册账号');

      return;
    }

    if (index < 0 || index >= _menuItems.length) return;
    if (_menuItems[index].adminOnly && !_accountStore.isAdministrator) {
      AppNotice.show(context, '仅管理员可访问该模块');
      return;
    }

    // 非中央卡片，先滑到中央。
    if ((_currentPage - index).abs() > 0.01) {
      await _pageController.animateToPage(
        index,
        duration: menuScrollDuration,
        curve: Curves.easeInOutCubic,
      );
      return;
    }

    setState(() {
      _openingModule = true;
    });

    ui.Image? backgroundSnapshot;

    try {
      // 等待暂停状态绘制完成。
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted) return;

      final cardBox = _cardKeys[index].currentContext?.findRenderObject();

      if (cardBox is! RenderBox) return;

      final sourceRect = Rect.fromPoints(
        cardBox.localToGlobal(Offset.zero),
        cardBox.localToGlobal(cardBox.size.bottomRight(Offset.zero)),
      );

      // 洗车和保养都捕获各自的当前画面。
      if (_menuItems[index].hasImageBackground) {
        final background = _backgroundKeys[index].currentContext
            ?.findRenderObject();

        if (background is RenderRepaintBoundary) {
          backgroundSnapshot = await background.toImage(pixelRatio: 2);
        }
      }

      if (!mounted) return;

      final route = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: pageEnterDuration,
        reverseTransitionDuration: pageReturnDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ModulePage(
            item: _menuItems[index],
            animation: animation,
            sourceRect: sourceRect,
            backgroundSnapshot: backgroundSnapshot,
            accountStore: _accountStore,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 放大、居中、渐隐都交给 ModulePage 控制。
          return child;
        },
      );

      await Navigator.of(context).push<void>(route);

      // 返回动画结束后，再释放过渡使用的图片。
      await route.completed;
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      backgroundSnapshot?.dispose();

      if (mounted) {
        setState(() {
          _openingModule = false;
        });
      }
    }
  }

  void _onAccountChanged() {
    if (!mounted) return;
    final admin = _accountStore.isAdministrator;
    if (admin != _showingAdmin) {
      // 角色改变时使用新的滚动控制器，避免普通菜单的第 4 页
      // 留在只有 2 页的管理员菜单里，或退出后出现越界/空白。
      final previous = _pageController;
      previous.removeListener(_updatePage);
      _pageController = PageController(viewportFraction: 0.30);
      _pageController.addListener(_updatePage);
      _currentPage = 0;
      _showingAdmin = admin;
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    setState(() {});
  }

  Future<void> _openAccountPage(bool register) {
    return _pushAccountRoute(
      AccountPage(
        register: register,
        store: _accountStore,
        enterDuration: pageEnterDuration,
        returnDuration: pageReturnDuration,
      ),
      returnToFirst: true,
    );
  }

  Future<void> _editProfile() async {
    if (_accountStore.currentUser == null) return;
    if (_accountStore.isAdministrator) {
      AppNotice.show(context, '演示管理员为固定账号，暂不支持修改资料');
      return;
    }
    await _pushAccountRoute(ProfileEditPage(store: _accountStore));
  }

  Future<void> _logout() async {
    if (_openingModule || !_introController.isCompleted) return;
    setState(() => _openingModule = true);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    try {
      if (reduceMotion) {
        _sessionController.value = 0;
      } else {
        await _sessionController.reverse().orCancel;
      }
      if (!mounted) return;
      await _accountStore.logout();
      if (!mounted) return;
      // 角色与滚动位置只在完全透明时改变，背景保持不动。
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      _currentPage = 0;
      await WidgetsBinding.instance.endOfFrame;
    } on TickerCanceled {
      // 页面已销毁，不继续退出或播放恢复动画。
      return;
    } catch (error) {
      if (mounted) AppNotice.show(context, error.toString());
    } finally {
      if (mounted) {
        try {
          if (reduceMotion) {
            _sessionController.value = 1;
          } else {
            await _sessionController.forward().orCancel;
          }
        } on TickerCanceled {
          // 恢复途中离开页面时取消即可。
        }
        if (mounted) setState(() => _openingModule = false);
      }
    }
  }

  Future<void> _pushAccountRoute(
    Widget page, {
    bool returnToFirst = false,
  }) async {
    if (!_introController.isCompleted || _openingModule) return;
    setState(() => _openingModule = true);
    try {
      final route = PageRouteBuilder<bool>(
        transitionDuration: pageEnterDuration,
        reverseTransitionDuration: pageReturnDuration,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = animation.drive(
            CurveTween(curve: Curves.easeInOutCubic),
          );
          return FadeTransition(
            opacity: curved,
            // 背景只渐显，不参与位移；同时平滑遮住旧菜单。
            // 否则透明页面会在动画结束时让旧卡片突然消失。
            child: AppBackground(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
      final succeeded = await Navigator.of(context).push<bool>(route);

      // 返回动画期间自动回到第一个模块；编辑资料则保留当前滚动位置。
      if (mounted &&
          succeeded == true &&
          returnToFirst &&
          _pageController.hasClients) {
        await _pageController.animateToPage(
          0,
          duration: pageReturnDuration,
          curve: Curves.easeInOutCubic,
        );
      }
      await route.completed;
    } finally {
      if (mounted) setState(() => _openingModule = false);
    }
  }

  @override
  void dispose() {
    _accountStore.onChanged = null;
    _pageController.removeListener(_updatePage);
    _pageController.dispose();
    _introController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _introController,
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 先用纯黑遮住背景图。文字完全消失后再移除黑色遮罩：
              // 2.8～4.0 秒渐显背景，背景稳定后才展开模块。
              if (!_introController.isCompleted)
                IgnorePointer(
                  child: Opacity(
                    opacity:
                        1.0 -
                        Curves.easeInOutCubic.transform(
                          _progress(7 / 15, 2 / 3),
                        ),
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),

              FadeTransition(
                key: const ValueKey('menu-session-transition'),
                opacity: _sessionOpacity,
                child: SlideTransition(
                  position: _sessionOffset,
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slotHeight = constraints.maxHeight * 0.30;
                        final remaining = (_menuItems.length - 1 - _currentPage)
                            .clamp(0.0, (_menuItems.length - 1).toDouble())
                            .toDouble();

                        // 越接近最后一个模块，账户按钮越清晰。
                        final accountOpacity = (1.0 - remaining)
                            .clamp(0.0, 1.0)
                            .toDouble();

                        // 按钮跟随最后一个模块移动，不固定在底部。
                        final accountTop =
                            constraints.maxHeight / 2 +
                            slotHeight / 2 +
                            12 +
                            remaining * slotHeight;

                        return IgnorePointer(
                          ignoring:
                              !_introController.isCompleted || _openingModule,
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.hardEdge,
                            children: [
                              PageView.builder(
                                key: ValueKey(_showingAdmin),
                                controller: _pageController,
                                scrollDirection: Axis.vertical,
                                itemCount: _menuItems.length,
                                itemBuilder: (context, index) {
                                  final item = _menuItems[index];
                                  final relative = index - _currentPage;
                                  final distance = relative
                                      .abs()
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                                  final isSelected = relative.abs() < 0.5;

                                  // 第 4 秒背景已显示完，再依次展开模块。
                                  // 保留原来的滚筒透视与由远及近效果。
                                  final start = 2 / 3 + index * 0.03;
                                  final end = 0.91 + index * 0.03;
                                  final reveal = Curves.easeOutCubic.transform(
                                    _progress(start, end),
                                  );

                                  final entranceScale = 0.42 + reveal * 0.58;
                                  final wheelScale = 1.0 - distance * 0.16;
                                  final scale = entranceScale * wheelScale;
                                  final unfoldOffset =
                                      -relative * slotHeight * (1.0 - reveal);
                                  final angle =
                                      relative.clamp(-1.5, 1.5) * 0.55 * reveal;
                                  final opacity =
                                      reveal * (1.0 - distance * 0.55);

                                  return Transform.translate(
                                    offset: Offset(0, unfoldOffset),
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, 0.0015)
                                        ..rotateX(angle)
                                        ..scaleByDouble(scale, scale, 1.0, 1.0),
                                      child: Opacity(
                                        opacity: opacity
                                            .clamp(0.0, 1.0)
                                            .toDouble(),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 16,
                                          ),
                                          child: MenuPanel(
                                            key: _cardKeys[index],
                                            item: item,
                                            selected: isSelected,
                                            pauseCarousel: _openingModule,
                                            backgroundKey:
                                                item.hasImageBackground
                                                ? _backgroundKeys[index]
                                                : null,
                                            onTap: () => _onCardTap(index),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Positioned(
                                top: accountTop,
                                left: 24,
                                right: 24,
                                child: IgnorePointer(
                                  ignoring: accountOpacity < 0.95,
                                  child: Opacity(
                                    opacity: accountOpacity,
                                    child: AccountActions(
                                      store: _accountStore,
                                      busy: _openingModule,
                                      onRegister: () => _openAccountPage(true),
                                      onLogin: () => _openAccountPage(false),
                                      onLogout: _logout,
                                    ),
                                  ),
                                ),
                              ),
                              if (_accountStore.currentUser != null)
                                Positioned.fill(
                                  child: UserProfileHeader(
                                    user: _accountStore.currentUser!,
                                    currentPage: _currentPage,
                                    onEdit: _editProfile,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 欢迎文字浮在同一页面上方，消失后不占布局空间。
              IgnorePointer(
                child: Center(
                  child: FadeTransition(
                    opacity: _welcomeOpacity,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '让爱车焕然一新',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEAF1FF),
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'A fresh ride. A fresh start.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                              color: Color(0xFF93A4BE),
                              letterSpacing: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// 同一张卡片在主菜单和模块页之间连续变化。
class ModuleHero extends StatelessWidget {
  final MenuItem item;
  final Widget child;

  const ModuleHero({super.key, required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'module_${item.title}',
      createRectTween: (begin, end) {
        return RectTween(begin: begin, end: end);
      },
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final value = direction == HeroFlightDirection.push
                    ? animation.value
                    : 1.0 - animation.value;

                return MenuPanel(item: item, selected: true, expansion: value);
              },
            );
          },
      child: child,
    );
  }
}

// expansion = 0：长条卡片。
// expansion = 1：铺满屏幕的模块背景。
class MenuPanel extends StatelessWidget {
  final MenuItem item;
  final bool selected;
  final double expansion;
  final double centerProgress;
  final bool pauseCarousel;
  final GlobalKey? backgroundKey;
  final ui.Image? backgroundSnapshot;
  final VoidCallback? onTap;

  const MenuPanel({
    super.key,
    required this.item,
    this.selected = true,
    this.expansion = 0,
    this.centerProgress = 0,
    this.pauseCarousel = false,
    this.backgroundKey,
    this.backgroundSnapshot,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWash = item.title == '洗车';
    final hasImageBackground = item.hasImageBackground;
    final radius = 24.0 * (1.0 - expansion);
    final iconSize = 48.0 + expansion * 24.0;
    final titleSize = 24.0 + expansion * 6.0;

    final headerAlignment = Alignment.lerp(
      Alignment.centerLeft,
      Alignment.center,
      centerProgress,
    )!;

    return Material(
      color: item.colors.first,
      elevation: (selected ? 8.0 : 2.0) * (1.0 - expansion),
      shadowColor: item.colors.first.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImageBackground)
            if (backgroundSnapshot != null)
              RawImage(image: backgroundSnapshot, fit: BoxFit.cover)
            else
              RepaintBoundary(
                key: backgroundKey,
                child: IgnorePointer(
                  child: isWash
                      ? WashImageCarousel(
                          transitionDuration: pageEnterDuration,
                          paused: pauseCarousel,
                        )
                      : ModuleImageCarousel(
                          images: item.imageAssets,
                          transitionDuration: pageEnterDuration,
                          paused: pauseCarousel,
                          fallbackColor: item.colors.first,
                          fallbackIcon: item.icon,
                        ),
                ),
              ),

          if (!hasImageBackground)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: item.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0x80000000),
                  Color(0x40000000),
                  Color(0x14000000),
                  Colors.transparent,
                ],
                stops: [0.0, 0.30, 0.65, 1.0],
              ),
            ),
          ),

          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: headerAlignment,
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: 28.0 * (1.0 - expansion),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                color: hasImageBackground
                                    ? Colors.black.withValues(alpha: 0.38)
                                    : Colors.white.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                item.icon,
                                size: 28.0 + expansion * 12.0,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.bold,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black38,
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.0 + expansion * 2.0,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 6,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Opacity(
                        opacity: 1.0 - expansion,
                        child: Icon(
                          selected
                              ? Icons.arrow_forward_ios
                              : Icons.circle_outlined,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 模块页：整屏延续被选卡片的渐变色。
class ModulePage extends StatelessWidget {
  final DemoAccountStore accountStore;
  final MenuItem item;
  final Animation<double> animation;
  final Rect sourceRect;
  final ui.Image? backgroundSnapshot;

  const ModulePage({
    super.key,
    required this.accountStore,
    required this.item,
    required this.animation,
    required this.sourceRect,
    this.backgroundSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fullScreenRect = Offset.zero & constraints.biggest;

          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final progress = animation.value;

              // 前 45%：卡片铺满屏幕。
              final expansion = const Interval(
                0.0,
                0.45,
                curve: Curves.easeInOutCubic,
              ).transform(progress);

              // 中间 30%：图标和文字移动到中央。
              final centerProgress = const Interval(
                0.45,
                0.75,
                curve: Curves.easeInOutCubic,
              ).transform(progress);

              // 最后 25%：封面渐隐，内容页渐显。
              final fadeProgress = const Interval(
                0.75,
                1.0,
                curve: Curves.easeInOut,
              ).transform(progress);

              final cardRect = Rect.lerp(
                sourceRect,
                fullScreenRect,
                expansion,
              )!;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 展开时逐渐遮住后面的主菜单。
                  Opacity(
                    opacity: expansion,
                    child: const ColoredBox(color: Color(0xFF0B1020)),
                  ),

                  // 真正的模块内容。
                  IgnorePointer(
                    ignoring: progress < 1.0,
                    child: Opacity(
                      opacity: fadeProgress,
                      child: _content(progress >= 1.0),
                    ),
                  ),

                  // 正在放大、居中并消失的封面。
                  Positioned.fromRect(
                    rect: cardRect,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 1.0 - fadeProgress,
                        child: MenuPanel(
                          item: item,
                          expansion: expansion,
                          centerProgress: centerProgress,
                          pauseCarousel: true,
                          backgroundSnapshot: backgroundSnapshot,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _content(bool active) {
    if (item.title == '充值') {
      return RechargePage(
        accountStore: accountStore,
        active: active,
        enterDuration: pageEnterDuration,
        returnDuration: pageReturnDuration,
        scrollDuration: menuScrollDuration,
      );
    }
    if (const {'洗车', '保养', '联系我们', '门店管理'}.contains(item.title)) {
      return StoreSelectionPage(
        accountStore: accountStore,
        service: item.title,
        active: active,
        enterDuration: pageEnterDuration,
        returnDuration: pageReturnDuration,
        scrollDuration: menuScrollDuration,
      );
    }
    if (item.title == '我的预约') {
      return BookingListPage(
        accountStore: accountStore,
        active: active,
        enterDuration: pageEnterDuration,
        returnDuration: pageReturnDuration,
        scrollDuration: menuScrollDuration,
      );
    }
    if (item.title == '用户管理') {
      return AdminUsersPage(
        accountStore: accountStore,
        active: active,
        enterDuration: pageEnterDuration,
        returnDuration: pageReturnDuration,
        scrollDuration: menuScrollDuration,
      );
    }
    return ModuleContent(item: item);
  }
}

// 模块真正打开后的页面。
// 后续的洗车服务、预约表单等，都放在这里。
class ModuleContent extends StatelessWidget {
  final MenuItem item;

  const ModuleContent({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B1020),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回主菜单',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title == '洗车' ? '选择适合爱车的洗护服务' : item.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFEAF1FF),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF93A4BE),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final List<String> imageAssets;
  final bool adminOnly;

  bool get hasImageBackground => title == '洗车' || imageAssets.isNotEmpty;

  const MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.imageAssets = const [],
    this.adminOnly = false,
  });
}
