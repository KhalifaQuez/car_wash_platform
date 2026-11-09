import 'dart:async';
import 'package:flutter/material.dart';

class WashImageCarousel extends StatefulWidget {
  final Duration transitionDuration;
  final bool paused;

  const WashImageCarousel({
    super.key,
    required this.transitionDuration,
    this.paused = false,
  });

  @override
  State<WashImageCarousel> createState() => _WashImageCarouselState();
}

class _WashImageCarouselState extends State<WashImageCarousel> {
  static const _images = [
    'assets/images/wash_1.JPG',
    'assets/images/wash_2.JPG',
    'assets/images/wash_3.JPG',
    'assets/images/wash_4.JPG',
    'assets/images/wash_5.JPG',
    'assets/images/wash_6.JPG',
  ];

  // 从较大的页码开始，图片通过取余循环使用。
  late final PageController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = PageController(initialPage: _images.length * 1000);

    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _nextImage());
  }

  void _nextImage() {
    if (!mounted ||
        widget.paused ||
        !_controller.hasClients ||
        !TickerMode.of(context)) {
      return;
    }

    if (_controller.position.isScrollingNotifier.value) {
      return;
    }

    final currentPage = _controller.page?.round();
    if (currentPage == null) return;

    _controller.animateToPage(
      currentPage + 1,
      duration: widget.transitionDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,

      // 新图片从左侧进入，原图片向右侧离开。
      reverse: true,
      scrollDirection: Axis.horizontal,

      // 图片自动轮播，让手势继续用于选择菜单。
      physics: const NeverScrollableScrollPhysics(),

      itemBuilder: (context, index) {
        return Image.asset(
          _images[index % _images.length],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(
              color: Color(0xFF193F77),
              child: Center(
                child: Icon(
                  Icons.local_car_wash_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
