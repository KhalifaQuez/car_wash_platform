import 'package:flutter/material.dart';
import '../models/demo_account_store.dart';
import '../models/booking_data.dart';
import '../models/store_revenue.dart';
import 'admin_store_page.dart';

class AdminStoreRevenuePage extends StatelessWidget {
  final DemoAccountStore accountStore;
  final String storeId;
  final Duration enterDuration, returnDuration;
  const AdminStoreRevenuePage({
    super.key,
    required this.accountStore,
    required this.storeId,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  Widget build(BuildContext context) => StoreManagementView(
    accountStore: accountStore,
    storeId: storeId,
    title: '门店营业额',
    builder: (context, settings) {
      final now = DateTime.now();
      final day = storeRevenueDay(now),
          month = storeRevenueDay(now, month: true);
      final reports = [
        accountStore.storeRevenue(
          storeId,
          fromUtc: day.fromUtc,
          toUtc: day.toUtc,
        ),
        accountStore.storeRevenue(
          storeId,
          fromUtc: month.fromUtc,
          toUtc: month.toUtc,
        ),
        accountStore.storeRevenue(storeId),
      ];
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '本机模拟营业额 · 成都时间 UTC+8',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Card(
              color: const Color(0xB33A2D50),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ['今日', '本月', '累计'][i],
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('模拟收款：${money(reports[i].receivedCents)}'),
                    Text('模拟退款：${money(reports[i].refundedCents)}'),
                    Text(
                      '净收入：${money(reports[i].netCents)}',
                      style: const TextStyle(
                        fontSize: 23,
                        color: Color(0xFFDCCAFF),
                      ),
                    ),
                    Text('付款订单：${reports[i].orderCount} 笔'),
                    if (reports[i].legacyNetCents != 0)
                      Text(
                        '含迁移前历史净额：${money(reports[i].legacyNetCents)}（无支付日期，不计今日或本月）',
                      ),
                  ],
                ),
              ),
            ),
          if (reports.last.unattributedCount > 0)
            Text('有 ${reports.last.unattributedCount} 条历史流水无法可靠归属门店，未计入本店。'),
          const SizedBox(height: 16),
          const Text(
            '不含充值、办卡款、升级费和余额修正。累计统计保留已删除订单的资金记录，退款按实际模拟退款日期计入。',
            style: TextStyle(color: Colors.white60, height: 1.6),
          ),
        ],
      );
    },
  );
}
