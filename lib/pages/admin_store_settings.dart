import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/demo_account_store.dart';
import '../models/store_management_data.dart';
import '../models/service_option_data.dart';
import '../widgets/booking_dialogs.dart';
import '../widgets/app_notice.dart';
import '../widgets/store_image.dart';

Future<void> editStoreStatus(
  BuildContext context,
  DemoAccountStore store,
  String id,
  Duration enter,
  Duration back,
) => _edit(context, store, id, enter, back, 'status');
Future<void> editStoreHours(
  BuildContext context,
  DemoAccountStore store,
  String id,
  Duration enter,
  Duration back,
) => _edit(context, store, id, enter, back, 'hours');
Future<void> editStoreProfile(
  BuildContext context,
  DemoAccountStore store,
  String id,
  Duration enter,
  Duration back,
) => _edit(context, store, id, enter, back, 'profile');
Future<void> _edit(
  BuildContext context,
  DemoAccountStore store,
  String id,
  Duration enter,
  Duration back,
  String kind,
) async {
  try {
    store.requireStoreAuthorization(id);
    await showBookingPopup<void>(
      context,
      (_) => _SettingsPopup(store: store, id: id, kind: kind),
      enter,
      back,
    );
  } catch (e) {
    if (context.mounted) AppNotice.show(context, e.toString());
  }
}

class _SettingsPopup extends StatefulWidget {
  final DemoAccountStore store;
  final String id, kind;
  const _SettingsPopup({
    required this.store,
    required this.id,
    required this.kind,
  });
  @override
  State<_SettingsPopup> createState() => _SettingsPopupState();
}

class _SettingsPopupState extends State<_SettingsPopup> {
  late final StoreSettings initial = widget.store.storeSettings(widget.id);
  late StoreSettings next = initial;
  late int openMinute = initial.openMinute, closeMinute = initial.closeMinute;
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.store.sessionRevision;
  }

  late final name = TextEditingController(text: initial.info.name);
  late final phone = TextEditingController(text: initial.info.phone);
  late final description = TextEditingController(text: initial.description);
  bool busy = false, closing = false;
  String? error;
  String time(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    description.dispose();
    super.dispose();
  }

  void finish() {
    if (busy || closing || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => closing = true);
    Navigator.of(context).pop();
  }

  Future<void> pick() async {
    if (busy || closing) return;
    setState(() => busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty || bytes.length > 256 * 1024)
        throw const FormatException('请选择压缩后不超过256KiB的图片');
      setState(
        () => next = next.copyWith(info: next.info.copyWith(imageBytes: bytes)),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || closing) return;
    setState(() => busy = true);
    try {
      if (widget.store.sessionRevision != session)
        throw const AccountValidationException('账号已重新登录，请重新进入门店');
      widget.store.requireStoreAuthorization(widget.id);
      if (widget.kind == 'hours')
        next = next.copyWith(openMinute: openMinute, closeMinute: closeMinute);
      if (widget.kind == 'profile')
        next = next.copyWith(
          info: next.info.copyWith(
            name: name.text.trim(),
            phone: phone.text.trim(),
          ),
          description: description.text.trim(),
        );
      await widget.store.saveStoreSettings(
        next,
        expectedRevision: initial.revision,
      );
      if (mounted) {
        setState(() {
          busy = false;
          closing = true;
        });
        Navigator.of(context).pop();
        AppNotice.show(context, '门店设置已保存');
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
      child: AbsorbPointer(
        absorbing: closing,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.kind == 'status'
                  ? '营业状态'
                  : widget.kind == 'hours'
                  ? '营业时间'
                  : '门店资料',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (widget.kind == 'status') ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(next.acceptingBookings ? '营业中' : '已关门'),
                subtitle: const Text('关门后暂停新预约，已有订单保留'),
                value: next.acceptingBookings,
                onChanged: busy
                    ? null
                    : (v) => setState(
                        () => next = next.copyWith(acceptingBookings: v),
                      ),
              ),
            ],
            if (widget.kind == 'hours') ...[
              for (final opening in [true, false])
                DropdownButtonFormField<int>(
                  initialValue: opening ? openMinute : closeMinute,
                  decoration: InputDecoration(
                    labelText: opening ? '首个到店时段' : '最后到店时段',
                  ),
                  items: [
                    for (var m = 0; m <= 1410; m += 30)
                      DropdownMenuItem(value: m, child: Text(time(m))),
                  ],
                  onChanged: busy
                      ? null
                      : (m) {
                          if (m == null) return;
                          setState(() {
                            if (opening) {
                              openMinute = m;
                            } else {
                              closeMinute = m;
                            }
                            error = null;
                          });
                        },
                ),
              const SizedBox(height: 16),
              const Text('临时休息日期（未来七天）'),
              for (final day in demoAppointmentDates(DateTime.now()))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(storeDateKey(day)),
                  value: next.closedDates.contains(storeDateKey(day)),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          final dates = {...next.closedDates};
                          if (v == true) {
                            dates.add(storeDateKey(day));
                          } else {
                            dates.remove(storeDateKey(day));
                          }
                          next = next.copyWith(closedDates: dates);
                        }),
                ),
            ],
            if (widget.kind == 'profile') ...[
              SizedBox(
                height: 130,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: StoreImage(next.info),
                ),
              ),
              TextButton(
                onPressed: busy ? null : pick,
                child: const Text('更换门店图片'),
              ),
              TextField(
                controller: name,
                maxLength: 40,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '门店名称'),
              ),
              TextField(
                controller: phone,
                maxLength: 20,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '联系电话（演示）'),
              ),
              TextField(
                controller: description,
                maxLength: 500,
                maxLines: 3,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '门店介绍'),
              ),
              Text(
                '定位参照地址：${initial.info.address}（本阶段不可修改）',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Color(0xFFFFC7D4)),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy || closing ? null : finish,
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
    ),
  );
}
