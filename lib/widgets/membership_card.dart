import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/recharge_data.dart';

class MembershipCard extends StatelessWidget {
  final CardTier tier;
  final bool selected;
  final CardAccount? account;
  final double angle;
  final double turn;
  const MembershipCard({
    super.key,
    required this.tier,
    required this.selected,
    this.account,
    this.angle = 0,
    this.turn = 0,
  });
  @override
  Widget build(BuildContext context) {
    final gold = tier != CardTier.basic;
    final accent = tier == CardTier.plus
        ? const Color(0xFFC6ABF0)
        : gold
        ? const Color(0xFFC8AE74)
        : const Color(0xFFC8C9CD);
    final progress = turn - turn.floorToDouble();
    final lightPosition = -3 + 6 * progress;
    final lightOpacity = MediaQuery.disableAnimationsOf(context)
        ? 0.0
        : math.sin(progress * math.pi) * .18;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, .001)
        ..rotateX(.13)
        ..rotateY(-.12 - math.sin(angle) * .42)
        ..rotateZ(-.035 + math.sin(angle) * .035),
      child: AspectRatio(
        aspectRatio: 1.586,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .35),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tier == CardTier.plus
                          ? const [
                              Color(0xFF33313F),
                              Color(0xFF111116),
                              Color(0xFF292035),
                            ]
                          : const [
                              Color(0xFF414247),
                              Color(0xFF151619),
                              Color(0xFF2A2B30),
                            ],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(-1, -.7),
                      end: const Alignment(1, .7),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: .10),
                        Colors.transparent,
                      ],
                      stops: const [.25, .43, .60],
                    ),
                  ),
                ),
                if (gold) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 38,
                    child: Container(height: 1, color: const Color(0x667D6B42)),
                  ),
                  Positioned(
                    right: 28,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: const Color(0x447D6B42)),
                  ),
                ],
                if (tier == CardTier.plus)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.bottomRight,
                        radius: 1.3,
                        colors: [
                          const Color(0xFF8860BB).withValues(alpha: .24),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('card-reflection'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(lightPosition - 1, -.6),
                        end: Alignment(lightPosition + 1, .6),
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: lightOpacity),
                          Colors.transparent,
                        ],
                        stops: const [.35, .5, .65],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '净车到家',
                              style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.auto_awesome_outlined,
                            color: accent,
                            size: 22,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        tier.label,
                        style: TextStyle(
                          color: accent,
                          fontSize: 30,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MEMBERSHIP  ·  ${(tier.discountPercent / 10).toStringAsFixed(tier == CardTier.pro ? 0 : 1)}折',
                        style: TextStyle(
                          color: accent.withValues(alpha: .8),
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        account?.tier == tier ? '已办理 · 演示充值卡' : '专属汽车服务卡',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MembershipCardWheel extends StatefulWidget {
  final CardTier selectedTier;
  final ValueChanged<CardTier> onSelected;
  final Duration duration;
  final CardAccount? account;
  const MembershipCardWheel({
    super.key,
    required this.selectedTier,
    required this.onSelected,
    required this.duration,
    this.account,
  });
  @override
  State<MembershipCardWheel> createState() => _MembershipCardWheelState();
}

class _MembershipCardWheelState extends State<MembershipCardWheel> {
  late double _turn = widget.selectedTier.index.toDouble();
  double _drag = 0;
  void _select(CardTier tier) {
    var delta = (tier.index - _turn.round()) % 3;
    if (delta == 2) delta = -1;
    setState(() => _turn += delta);
    widget.onSelected(tier);
  }

  @override
  void didUpdateWidget(MembershipCardWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_turn.round() % 3 != widget.selectedTier.index) {
      var delta = (widget.selectedTier.index - _turn.round()) % 3;
      if (delta == 2) delta = -1;
      _turn += delta;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(constraints.maxWidth * .75, 430.0);
      return SizedBox(
        height: width / 1.586 + 64,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _drag = 0,
          onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
          onHorizontalDragEnd: (d) {
            final velocity = d.primaryVelocity ?? 0;
            if (_drag.abs() < 24 && velocity.abs() < 150) return;
            final direction = velocity.abs() >= 150 ? velocity : _drag;
            _select(
              CardTier.values[(_turn.round() + (direction < 0 ? 1 : -1)) % 3],
            );
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _turn),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : widget.duration,
            curve: Curves.easeInOutCubic,
            builder: (context, turn, child) {
              final tiers = CardTier.values.toList()
                ..sort(
                  (a, b) => math
                      .cos((a.index - turn) * math.pi * 2 / 3)
                      .compareTo(math.cos((b.index - turn) * math.pi * 2 / 3)),
                );
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  for (final tier in tiers)
                    Builder(
                      builder: (context) {
                        final angle = (tier.index - turn) * math.pi * 2 / 3;
                        final depth = (math.cos(angle) + 1) / 2;
                        return Transform.translate(
                          offset: Offset(
                            math.sin(angle) * constraints.maxWidth * .29,
                            (1 - depth) * 16,
                          ),
                          child: Transform(
                            transform: Matrix4.identity()
                              ..scaleByDouble(
                                .65 + .35 * depth,
                                .65 + .35 * depth,
                                1,
                                1,
                              ),
                            alignment: Alignment.center,
                            child: Semantics(
                              button: true,
                              selected: tier == widget.selectedTier,
                              label: '${tier.label}会员卡',
                              child: GestureDetector(
                                onTap: () => _select(tier),
                                child: Opacity(
                                  opacity: .55 + .45 * depth,
                                  child: SizedBox(
                                    width: width,
                                    child: MembershipCard(
                                      tier: tier,
                                      selected: tier == widget.selectedTier,
                                      account: widget.account,
                                      angle: angle,
                                      turn: turn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
