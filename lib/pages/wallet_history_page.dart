import 'package:flutter/material.dart';
import '../models/booking_data.dart';
import '../models/demo_account_store.dart';
import '../models/recharge_data.dart';

class WalletHistoryPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final String userId;
  final Duration enterDuration, returnDuration;
  const WalletHistoryPage({
    super.key,
    required this.accountStore,
    required this.userId,
    required this.enterDuration,
    required this.returnDuration,
  });
  @override
  State<WalletHistoryPage> createState() => _WalletHistoryPageState();
}

class _WalletHistoryPageState extends State<WalletHistoryPage> {
  WalletEntryKind? _filter;
  @override
  void initState() {
    super.initState();
    widget.accountStore.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.accountStore.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<WalletEntry> entries;
    try {
      entries = widget.accountStore
          .walletEntriesFor(widget.userId)
          .where((e) => _filter == null || e.kind == _filter)
          .toList();
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('交易记录')),
        body: const Center(child: Text('账号权限已变化，请返回')),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/store_background.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('充值与消费记录'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final filter in <WalletEntryKind?>[
                    null,
                    WalletEntryKind.recharge,
                    WalletEntryKind.payment,
                    WalletEntryKind.issue,
                    WalletEntryKind.upgrade,
                  ])
                    TextButton(
                      onPressed: () => setState(() => _filter = filter),
                      child: Text(
                        '${filter?.label ?? '全部'}${_filter == filter ? ' ✓' : ''}',
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('暂无记录'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Card(
                          color: const Color(0xB32C223E),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.kind.label,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      entry.chargedCents > 0
                                          ? '支付 ${money(entry.chargedCents)}'
                                          : '${entry.deltaCents > 0 ? '+' : ''}${money(entry.deltaCents)}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(entry.summary),
                                if (entry.chargedCents > 0) ...[
                                  Text(
                                    '卡余额变动：${entry.deltaCents > 0 ? '+' : ''}${money(entry.deltaCents)}',
                                  ),
                                  Text(
                                    entry.kind == WalletEntryKind.issue
                                        ? '办理款已全额计入卡内余额'
                                        : '升级费不计入卡内余额',
                                  ),
                                ],
                                if (entry.method != null)
                                  Text('方式：${entry.method!.label}'),
                                Text('卡余额：${money(entry.balanceAfterCents)}'),
                                if (entry.reason.isNotEmpty)
                                  Text('原因：${entry.reason}'),
                                if (entry.bookingId != null)
                                  Text(
                                    '预约：${entry.bookingId}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white60,
                                    ),
                                  ),
                                Text(
                                  entry.at
                                      .toLocal()
                                      .toString()
                                      .split('.')
                                      .first,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '全部为本机演示流水，无真实资金交易。',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
