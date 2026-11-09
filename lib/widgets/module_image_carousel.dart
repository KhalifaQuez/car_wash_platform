import 'dart:async';
import 'package:flutter/material.dart';

/// 通用模块背景轮播。保养先使用它，之后可复用于充值、联系我们。
class ModuleImageCarousel extends StatefulWidget {
  final List<String> images;
  final Duration transitionDuration;
  final bool paused;
  final Color fallbackColor;
  final IconData fallbackIcon;

  const ModuleImageCarousel({
    super.key,
    required this.images,
    required this.transitionDuration,
    this.paused = false,
    this.fallbackColor = const Color(0xFF2B2354),
    this.fallbackIcon = Icons.build_outlined,
  });

  @override
  State<ModuleImageCarousel> createState() => _ModuleImageCarouselState();
}

class _ModuleImageCarouselState extends State<ModuleImageCarousel> {
  late final PageController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 从较大页码开始，通过取余无限轮播。
    _controller = PageController(initialPage: widget.images.length * 1000);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _nextImage());
  }

  void _nextImage() {
    if (!mounted ||
        widget.paused ||
        widget.images.length < 2 ||
        !_controller.hasClients ||
        !TickerMode.getValuesNotifier(context).value.enabled) {
      return;
    }
    if (_controller.position.isScrollingNotifier.value) return;
    final currentPage = _controller.page?.round();
    if (currentPage == null) return;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(currentPage + 1);
    } else {
      _controller.animateToPage(
        currentPage + 1,
        duration: widget.transitionDuration,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _fallback() {
    return ColoredBox(
      color: widget.fallbackColor,
      child: Center(
        child: Icon(widget.fallbackIcon, color: Colors.white54, size: 64),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return _fallback();
    return PageView.builder(
      controller: _controller,
      // 与洗车一致：新图片从左侧进入，旧图片向右侧离开。
      reverse: true,
      scrollDirection: Axis.horizontal,
      // 不占用手势，仍通过上下滑动选择模块。
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Image.asset(
          widget.images[index % widget.images.length],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        );
      },
    );
  }
}
