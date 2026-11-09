import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import 'store_image.dart';

class BookingWheel extends StatefulWidget {
  final List<Booking> bookings;
  final Map<String, String> ownerLabels;
  final bool active;
  final bool busy;
  final Duration scrollDuration;
  final void Function(Booking, Rect) onOpen;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<Booking>? onToggle;
  const BookingWheel({
    super.key,
    required this.bookings,
    this.ownerLabels = const {},
    required this.active,
    required this.busy,
    required this.scrollDuration,
    required this.onOpen,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggle,
  });
  @override
  State<BookingWheel> createState() => _BookingWheelState();
}

class _BookingWheelState extends State<BookingWheel> {
  PageController? _controller;
  double _fraction = 0;
  double _page = 0;
  bool _centering = false;
  final Map<String, GlobalKey> _keys = {};
  String get _signature =>
      widget.bookings.map((booking) => booking.id).join('|');

  @override
  void didUpdateWidget(covariant BookingWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookings.map((booking) => booking.id).join('|') !=
        _signature) {
      final old = _controller;
      old?.removeListener(_track);
      _controller = null;
      _page = widget.bookings.isEmpty
          ? 0
          : _page.round().clamp(0, widget.bookings.length - 1).toDouble();
      _keys.removeWhere(
        (key, value) => !widget.bookings.any((booking) => booking.id == key),
      );
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
  }

  void _track() {
    if (mounted && _controller?.hasClients == true) {
      setState(() => _page = _controller!.page ?? 0);
    }
  }

  PageController _for(double fraction) {
    if (_controller == null || (fraction - _fraction).abs() > 0.001) {
      final old = _controller;
      old?.removeListener(_track);
      _fraction = fraction;
      _controller = PageController(
        initialPage: _page.round(),
        viewportFraction: fraction,
      )..addListener(_track);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _controller!;
  }

  Future<void> _tap(int index) async {
    if (!widget.active ||
        widget.busy ||
        _centering ||
        _controller?.hasClients != true) {
      return;
    }
    if ((_page - index).abs() > 0.01) {
      if (widget.selectionMode) {
        widget.onToggle?.call(widget.bookings[index]);
        return;
      }
      setState(() => _centering = true);
      try {
        await _controller!.animateToPage(
          index,
          duration: widget.scrollDuration,
          curve: Curves.easeInOutCubic,
        );
      } finally {
        if (mounted) setState(() => _centering = false);
      }
      return;
    }
    final booking = widget.bookings[index];
    if (widget.selectionMode) {
      widget.onToggle?.call(booking);
      return;
    }
    final box = _keys[booking.id]?.currentContext?.findRenderObject();
    if (box is RenderBox) {
      widget.onOpen(booking, box.localToGlobal(Offset.zero) & box.size);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_track);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bookings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            '暂无符合条件的预约\n提交预约后会出现在这里',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFD2C4E3), height: 1.8),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final target =
            (constraints.maxHeight * 0.30).clamp(210.0, 280.0) +
            (scale - 1).clamp(0.0, 3.0) * 100;
        final fraction = ((target + 20) / constraints.maxHeight)
            .clamp(0.30, 0.94)
            .toDouble();
        return IgnorePointer(
          ignoring: widget.busy || !widget.active,
          child: PageView.builder(
            key: ValueKey('$_signature:$fraction'),
            controller: _for(fraction),
            scrollDirection: Axis.vertical,
            itemCount: widget.bookings.length,
            itemBuilder: (context, index) {
              final booking = widget.bookings[index];
              final relative = index - _page;
              final distance = relative.abs().clamp(0.0, 1.0);
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
                    child: BookingCard(
                      key: _keys.putIfAbsent(booking.id, GlobalKey.new),
                      booking: booking,
                      ownerLabel: widget.ownerLabels[booking.ownerId],
                      onTap: () => _tap(index),
                      selectionMode: widget.selectionMode,
                      checked: widget.selectedIds.contains(booking.id),
                      onChecked: widget.busy || !widget.active
                          ? null
                          : (_) => widget.onToggle?.call(booking),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class BookingCard extends StatelessWidget {
  final Booking booking;
  final String? ownerLabel;
  final VoidCallback? onTap;
  final double expansion;
  final double centerProgress;
  final bool selectionMode;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  const BookingCard({
    super.key,
    required this.booking,
    this.ownerLabel,
    this.onTap,
    this.expansion = 0,
    this.centerProgress = 0,
    this.selectionMode = false,
    this.checked = false,
    this.onChecked,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF251735),
    borderRadius: BorderRadius.circular(22 * (1 - expansion)),
    elevation: 6 * (1 - expansion),
    shadowColor: const Color(0x665C397F),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      fit: StackFit.expand,
      children: [
        StoreImage(booking.store),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xCC000000), Color(0x88000000), Color(0x22000000)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.lerp(
                    Alignment.centerLeft,
                    Alignment.center,
                    centerProgress,
                  )!,
                  child: SizedBox(
                    width:
                        constraints.maxWidth * (1 - centerProgress) +
                        constraints.maxWidth.clamp(0.0, 340.0) * centerProgress,
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: constraints.maxWidth.clamp(0.0, 310.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.store.name,
                                    style: TextStyle(
                                      fontSize: 18 + expansion * 6,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (ownerLabel != null)
                                    Text(
                                      ownerLabel!,
                                      style: const TextStyle(
                                        color: Color(0xFFE0D3FF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  Text(
                                    '${booking.draft.service} · ${booking.draft.selections[0].summary}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    booking.store.address,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '电话 ${booking.store.phone}（演示）',
                                    style: const TextStyle(
                                      color: Color(0xFFD2C4E3),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${booking.hiddenFromCustomer ? '用户已删除 · ' : ''}${booking.statusLabel} · 演示 ${money(booking.amountCents)}',
                                    style: const TextStyle(
                                      color: Color(0xFFE4D3FF),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (expansion < 1 && !selectionMode)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.chevron_right,
                              color: Colors.white,
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
        if (selectionMode)
          Positioned(
            right: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC281B37),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Checkbox(
                key: ValueKey('booking-checkbox-${booking.id}'),
                value: checked,
                onChanged: onChecked,
                activeColor: const Color(0xFFB18ADD),
                checkColor: Colors.white,
              ),
            ),
          ),
      ],
    ),
  );
}
