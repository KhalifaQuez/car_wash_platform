import 'package:flutter/material.dart';
import '../models/demo_account_store.dart';
import '../models/store_management_data.dart';
import '../models/recharge_data.dart';
import '../models/service_pricing.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_dialogs.dart';
import 'admin_store_page.dart';

class AdminStoreServicesPage extends StatelessWidget {
  final DemoAccountStore accountStore;
  final String storeId;
  final Duration enterDuration, returnDuration;
  const AdminStoreServicesPage({
    super.key,
    required this.accountStore,
    required this.storeId,
    required this.enterDuration,
    required this.returnDuration,
  });
  Future<void> edit(
    BuildContext context,
    StoreSettings settings,
    StoreServiceItem item,
  ) async {
    await showBookingPopup<void>(
      context,
      (_) => _ItemEditor(store: accountStore, settings: settings, item: item),
      enterDuration,
      returnDuration,
    );
  }

  @override
  Widget build(BuildContext context) => StoreManagementView(
    accountStore: accountStore,
    storeId: storeId,
    title: '服务项目',
    builder: (context, settings) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '按门店配置，已提交订单不会自动改价。预约时间和文字备注不收费。',
          style: TextStyle(color: Colors.white60),
        ),
        for (final service in ['洗车', '保养']) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(service, style: const TextStyle(fontSize: 23)),
          ),
          for (final item in settings.items.where((i) => i.service == service))
            Card(
              color: const Color(0xA3332945),
              child: ListTile(
                title: Text(item.choice),
                subtitle: Text(
                  '${['', '套餐', '用品', '额外需求'][item.section]} · ${item.enabled ? '已上架' : '已下架'}',
                ),
                trailing: Text(priceMoney(item.cents)),
                onTap: () => edit(context, settings, item),
              ),
            ),
        ],
      ],
    ),
  );
}

class _ItemEditor extends StatefulWidget {
  final DemoAccountStore store;
  final StoreSettings settings;
  final StoreServiceItem item;
  const _ItemEditor({
    required this.store,
    required this.settings,
    required this.item,
  });
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final input = TextEditingController(
    text: (widget.item.cents / 100).toStringAsFixed(2),
  );
  late bool enabled = widget.item.enabled;
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.store.sessionRevision;
  }

  bool busy = false, closing = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || closing) return;
    setState(() => busy = true);
    try {
      if (session != widget.store.sessionRevision)
        throw const AccountValidationException('账号已改变');
      final cents = RegExp(r'^0(?:\.0{1,2})?$').hasMatch(input.text.trim())
          ? 0
          : parseRechargeCents(input.text);
      final updated = widget.settings.copyWith(
        items: [
          for (final i in widget.settings.items)
            i.key == widget.item.key
                ? i.copyWith(cents: cents, enabled: enabled)
                : i,
        ],
      );
      await widget.store.saveStoreSettings(
        updated,
        expectedRevision: widget.settings.revision,
      );
      if (mounted) {
        setState(() {
          busy = false;
          closing = true;
        });
        Navigator.of(context).pop();
        AppNotice.show(context, '服务项目已保存');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted && !closing) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: BookingPopupSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.item.choice, style: const TextStyle(fontSize: 22)),
          TextField(
            controller: input,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '价格（元，最多两位小数）'),
          ),
          SwitchListTile(
            title: const Text('上架'),
            value: enabled,
            onChanged: busy ? null : (v) => setState(() => enabled = v),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Color(0xFFFFC7D4))),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || closing
                      ? null
                      : () {
                          if (ModalRoute.of(context)?.isCurrent != true) return;
                          setState(() => closing = true);
                          Navigator.of(context).pop();
                        },
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy || closing ? null : save,
                  child: Text(busy ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
