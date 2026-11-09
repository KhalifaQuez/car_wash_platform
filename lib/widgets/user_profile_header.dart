import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../models/demo_account_store.dart';

class UserAvatar extends StatelessWidget {
  final Uint8List? avatarBytes;
  final double size;
  final VoidCallback? onTap;
  final String tooltip;

  const UserAvatar({
    super.key,
    required this.avatarBytes,
    required this.size,
    this.onTap,
    this.tooltip = '编辑个人资料',
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Icon(
      Icons.person_outline,
      size: size * 0.52,
      color: const Color(0xFFEAF1FF),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: onTap != null,
        label: tooltip,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF657DA6), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: const Color(0xFF1B2942),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: avatarBytes == null
                  ? fallback()
                  : Image.memory(
                      avatarBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 512,
                      errorBuilder: (context, error, stackTrace) => fallback(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// 保留同一枚头像；位置和大小直接由滚动进度决定，反向滚动自然还原。
class UserProfileHeader extends StatelessWidget {
  final UserProfile user;
  final double currentPage;
  final VoidCallback onEdit;
  const UserProfileHeader({
    super.key,
    required this.user,
    required this.currentPage,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compact = height < 400;
        final homeSize = compact ? 48.0 : 76.0;
        const dockSize = 42.0;
        const dockTop = 12.0;
        final slotHeight = height * 0.30;
        final headerHeight = homeSize + (compact ? 38.0 : 64.0);
        final homeTop = math.max(dockTop, (height * 0.35 - headerHeight) / 2);
        final travel = math.max(0.0, currentPage) * slotHeight;
        final collapseStart = math.max(0.0, homeTop - dockTop);
        final collapseDistance = math.max(64.0, slotHeight * 0.60);
        final rawProgress = ((travel - collapseStart) / collapseDistance)
            .clamp(0.0, 1.0)
            .toDouble();
        final progress = Curves.easeInOutCubic.transform(rawProgress);

        // 随模块移至顶部后停靠，头像不移出屏幕，也不渐隐。
        final followedTop = math.max(dockTop, homeTop - travel);
        final size = lerpDouble(homeSize, dockSize, progress)!;
        final left = lerpDouble(
          (width - homeSize) / 2,
          width - 24 - dockSize,
          progress,
        )!;
        final top = lerpDouble(followedTop, dockTop, progress)!;
        final labelOpacity = (1.0 - progress * 1.8).clamp(0.0, 1.0).toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: top + size + 12,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Opacity(
                  opacity: labelOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '欢迎，' + user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFEAF1FF),
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 6),
                        const Text(
                          '让每一次出行，都焕然一新。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF93A4BE),
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: top,
              left: left,
              child: UserAvatar(
                avatarBytes: user.avatarBytes,
                size: size,
                onTap: onEdit,
              ),
            ),
          ],
        );
      },
    );
  }
}
