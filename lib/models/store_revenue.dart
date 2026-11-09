import 'recharge_data.dart';

class StoreRevenueSummary {
  final int receivedCents,
      refundedCents,
      orderCount,
      legacyNetCents,
      unattributedCount;
  int get netCents => receivedCents - refundedCents + legacyNetCents;
  const StoreRevenueSummary({
    required this.receivedCents,
    required this.refundedCents,
    required this.orderCount,
    required this.legacyNetCents,
    required this.unattributedCount,
  });
}

StoreRevenueSummary summarizeStoreRevenue(
  String storeId,
  Iterable<WalletEntry> entries, {
  DateTime? fromUtc,
  DateTime? toUtc,
  int legacyNetCents = 0,
  int unattributedCount = 0,
}) {
  var received = 0, refunded = 0;
  final orders = <String>{};
  for (final e in entries) {
    if (e.storeId != storeId ||
        e.bookingId == null ||
        (fromUtc != null && e.at.isBefore(fromUtc)) ||
        (toUtc != null && !e.at.isBefore(toUtc)))
      continue;
    if (e.kind == WalletEntryKind.payment) {
      received -= e.deltaCents;
      orders.add(e.bookingId!);
    }
    if (e.kind == WalletEntryKind.refund) refunded += e.deltaCents;
  }
  return StoreRevenueSummary(
    receivedCents: received,
    refundedCents: refunded,
    orderCount: orders.length,
    legacyNetCents: fromUtc == null && toUtc == null ? legacyNetCents : 0,
    unattributedCount: unattributedCount,
  );
}

({DateTime fromUtc, DateTime toUtc}) storeRevenueDay(
  DateTime instant, {
  bool month = false,
}) {
  final chengdu = instant.toUtc().add(const Duration(hours: 8));
  final start = DateTime.utc(
    chengdu.year,
    chengdu.month,
    month ? 1 : chengdu.day,
  );
  final end = month
      ? DateTime.utc(chengdu.year, chengdu.month + 1, 1)
      : start.add(const Duration(days: 1));
  return (
    fromUtc: start.subtract(const Duration(hours: 8)),
    toUtc: end.subtract(const Duration(hours: 8)),
  );
}
