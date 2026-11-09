import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 所有页面统一调用：AppNotice.show(context, '提示内容')。
class AppNotice {
  AppNotice._();

  static void show(BuildContext context, String message) {
    final scope = context.getInheritedWidgetOfExactType<_NoticeScope>();
    if (scope == null) {
      throw FlutterError('请先在 MaterialApp.builder 中添加 AppNoticeHost。');
    }
    scope.host.show(message);
  }
}

/// 放在 MaterialApp.builder 内，覆盖整个应用，但不拦截点击和滑动。
class AppNoticeHost extends StatefulWidget {
  final Widget child;
  final Duration enterDuration;
  final Duration stayDuration;
  final Duration exitDuration;

  const AppNoticeHost({
    super.key,
    required this.child,
    this.enterDuration = const Duration(milliseconds: 1200),
    this.stayDuration = const Duration(seconds: 2),
    this.exitDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<AppNoticeHost> createState() => _AppNoticeHostState();
}

class _AppNoticeHostState extends State<AppNoticeHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _holdTimer;
  String? _message;
  bool _leaving = false;
  bool _reduceMotion = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.enterDuration,
      reverseDuration: widget.exitDuration,
    );
  }

  @override
  void didUpdateWidget(covariant AppNoticeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..duration = widget.enterDuration
      ..reverseDuration = widget.exitDuration;
  }

  void show(String message) {
    if (!mounted || message.trim().isEmpty) return;
    final generation = ++_generation;
    _holdTimer?.cancel();
    _controller.stop();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _message = message;
      _leaving = false;
    });

    // 连续点击时只显示最新的一条，不排队、不叠加多个气泡。
    if (_reduceMotion) {
      _controller.value = 1;
      _scheduleExit(generation);
    } else {
      _controller.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && generation == _generation) {
          _scheduleExit(generation);
        }
      });
    }
  }

  void _scheduleExit(int generation) {
    _holdTimer = Timer(widget.stayDuration, () => _exit(generation));
  }

  void _exit(int generation) {
    if (!mounted || generation != _generation) return;
    if (_reduceMotion) {
      setState(() => _message = null);
      return;
    }
    setState(() => _leaving = true);
    _controller.reverse(from: 1).whenCompleteOrCancel(() {
      if (mounted && generation == _generation) {
        setState(() => _message = null);
      }
    });
  }

  @override
  void dispose() {
    // 先使旧动画回调失效，避免在销毁过程中更新页面。
    _generation++;
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NoticeScope(
      host: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_message != null)
            Positioned(
              left: 24,
              right: 24,
              // 键盘打开时，气泡浮在键盘上方；同时避开系统导航区域。
              bottom:
                  MediaQuery.viewInsetsOf(context).bottom +
                  MediaQuery.viewPaddingOf(context).bottom +
                  28,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final value = _controller.value;
                    final enter = Curves.easeOutCubic.transform(value);
                    final exit = Curves.easeInOutCubic.transform(1 - value);
                    final opacity = _leaving ? 1 - exit : enter;
                    final offsetY = _leaving ? -32 * exit : 48 * (1 - enter);
                    final scale = _leaving
                        ? 1 + 0.16 * exit
                        : 0.96 + 0.04 * enter;
                    final blur = _leaving ? 7.0 * exit : 0.0;

                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0).toDouble(),
                      child: Transform.translate(
                        offset: Offset(0, offsetY),
                        child: Transform.scale(
                          scale: scale,
                          child: ImageFiltered(
                            enabled: _leaving,
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: blur,
                              sigmaY: blur,
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                  child: Center(
                    // 短提示紧贴文字，长提示自动换行，不再横跨整屏。
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Semantics(
                        liveRegion: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 12,
                                sigmaY: 12,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  // 半透明暗色玻璃，不是白色底条。
                                  color: const Color(0x99121B2B),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: const Color(0x30FFFFFF),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 15,
                                  ),
                                  child: Text(
                                    _message!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFF1F5FF),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 1.45,
                                      letterSpacing: 0.4,
                                      decoration: TextDecoration.none,
                                      shadows: [
                                        Shadow(
                                          color: Color(0x66000000),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
}

class _NoticeScope extends InheritedWidget {
  final _AppNoticeHostState host;

  const _NoticeScope({required this.host, required super.child});

  @override
  bool updateShouldNotify(_NoticeScope oldWidget) => host != oldWidget.host;
}
