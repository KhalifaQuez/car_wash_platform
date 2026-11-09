import 'package:flutter/material.dart';

/// 全应用共用一张静止背景，放在 Navigator 后面。
/// 主菜单、登录/注册和资料页使用透明 Scaffold 显示它；
/// 模块内容页保留自己的原有背景。
class AppBackground extends StatelessWidget {
  static const assetPath = 'assets/images/menu_background.JPG';
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0B1020)),
        Positioned.fill(
          child: IgnorePointer(
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              // 图片未放入或尚未登记时，保留暗色底，避免页面报红。
              // 如果看不到背景，请检查文件名、资源登记并完整重启。
              errorBuilder: (context, error, stackTrace) {
                return const ColoredBox(color: Color(0xFF0B1020));
              },
            ),
          ),
        ),
        child,
      ],
    );
  }
}
