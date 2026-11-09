import 'package:flutter/material.dart';

class StoreStatusBadge extends StatelessWidget {
  final bool acceptingBookings;
  const StoreStatusBadge({super.key, required this.acceptingBookings});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: acceptingBookings
          ? const Color(0xCC173D32)
          : const Color(0xCC393245),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      acceptingBookings ? '● 营业中' : '● 已关门',
      style: TextStyle(
        color: acceptingBookings
            ? const Color(0xFFB5F0CF)
            : const Color(0xFFE0D1EE),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
