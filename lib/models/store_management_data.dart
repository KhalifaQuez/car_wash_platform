import 'store_info.dart';
import 'service_pricing.dart';
import 'recharge_data.dart';
import 'service_option_data.dart';
import 'booking_data.dart';

const storeManagementCodes = {
  'taikoo': 'A00001',
  'tianfu': 'A00002',
  'wuhou': 'A00003',
  'caotang': 'A00004',
  'huanhua': 'A00005',
  'jinsha': 'A00006',
  'global': 'A00007',
};

class StoreServiceItem {
  final String service, choice;
  final int section, cents;
  final bool enabled;
  const StoreServiceItem({
    required this.service,
    required this.section,
    required this.choice,
    required this.cents,
    this.enabled = true,
  });
  String get key => '$service:$section:$choice';
  StoreServiceItem copyWith({int? cents, bool? enabled}) => StoreServiceItem(
    service: service,
    section: section,
    choice: choice,
    cents: cents ?? this.cents,
    enabled: enabled ?? this.enabled,
  );
  Map<String, dynamic> toJson() => {
    'service': service,
    'section': section,
    'choice': choice,
    'cents': cents,
    'enabled': enabled,
  };
  factory StoreServiceItem.fromJson(Map<String, dynamic> data) {
    if (data['service'] is! String ||
        data['section'] is! int ||
        data['choice'] is! String ||
        data['cents'] is! int ||
        data['enabled'] is! bool)
      throw const FormatException('服务项目损坏');
    return StoreServiceItem(
      service: data['service'],
      section: data['section'],
      choice: data['choice'],
      cents: data['cents'],
      enabled: data['enabled'],
    );
  }
}

String storeDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<DateTime> storeAppointmentSlots(
  StoreSettings settings,
  DateTime day,
  DateTime now,
) {
  if (settings.closedDates.contains(storeDateKey(day)) ||
      !demoAppointmentDates(
        now,
      ).any((d) => storeDateKey(d) == storeDateKey(day)))
    return const [];
  return [
    for (
      var minute = settings.openMinute;
      minute <= settings.closeMinute;
      minute += 30
    )
      if (DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      ).isAfter(now))
        DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60),
  ];
}

List<ServicePriceLine> quoteStoreSelections(
  StoreSettings settings,
  String service,
  List<ServiceOptionSelection?> selections, {
  Booking? existing,
}) {
  if (selections.length != 4 || serviceOptionsFor(service).isEmpty)
    throw const FormatException('服务选项无效');
  final lines = List<ServicePriceLine>.unmodifiable([
    if (selections[0]?.appointment != null)
      const ServicePriceLine(0, '预约到店时间', 0),
    for (var section = 1; section < 4; section++)
      for (final choice in selections[section]?.choices ?? <String>{})
        _quoteStoreItem(settings, service, section, choice, existing),
    if (selections[3]?.note.trim().isNotEmpty == true)
      const ServicePriceLine(3, '文字备注', 0),
  ]);
  validateMoney(priceTotal(lines));
  return lines;
}

ServicePriceLine _quoteStoreItem(
  StoreSettings settings,
  String service,
  int section,
  String choice,
  Booking? existing,
) {
  final old = existing?.effectivePriceLines
      .where((p) => p.section == section && p.label == choice)
      .firstOrNull;
  if (old != null && existing!.draft.service == service) return old;
  final item = settings.item(service, section, choice);
  if (!item.enabled) throw const FormatException('选择的项目已下架，请重新选择');
  return ServicePriceLine(section, choice, item.cents);
}

class StoreSettings {
  final StoreInfo info;
  final String description;
  final bool acceptingBookings;
  final int openMinute, closeMinute, revision;
  final Set<String> closedDates;
  final List<StoreServiceItem> items;
  StoreSettings({
    required this.info,
    this.description = '演示门店，为您提供洗车与保养服务。',
    this.acceptingBookings = true,
    this.openMinute = 540,
    this.closeMinute = 1080,
    this.revision = 0,
    Set<String> closedDates = const {},
    required List<StoreServiceItem> items,
  }) : closedDates = Set.unmodifiable(closedDates),
       items = List.unmodifiable(items) {
    validate();
  }
  factory StoreSettings.defaults(StoreInfo info) => StoreSettings(
    info: info,
    items: [
      for (final service in demoServicePrices.entries)
        for (final section in service.value.entries)
          for (final price in section.value.entries)
            StoreServiceItem(
              service: service.key,
              section: section.key,
              choice: price.key,
              cents: price.value,
            ),
    ],
  );
  StoreSettings copyWith({
    StoreInfo? info,
    String? description,
    bool? acceptingBookings,
    int? openMinute,
    int? closeMinute,
    int? revision,
    Set<String>? closedDates,
    List<StoreServiceItem>? items,
  }) => StoreSettings(
    info: info ?? this.info,
    description: description ?? this.description,
    acceptingBookings: acceptingBookings ?? this.acceptingBookings,
    openMinute: openMinute ?? this.openMinute,
    closeMinute: closeMinute ?? this.closeMinute,
    revision: revision ?? this.revision,
    closedDates: closedDates ?? this.closedDates,
    items: items ?? this.items,
  );
  StoreServiceItem item(String service, int section, String choice) =>
      items.firstWhere(
        (item) =>
            item.service == service &&
            item.section == section &&
            item.choice == choice,
        orElse: () => throw const FormatException('服务项目不存在'),
      );
  void validate() {
    final base = demoStores.where((s) => s.id == info.id).firstOrNull;
    if (base == null ||
        base.address != info.address ||
        base.referencePlace != info.referencePlace ||
        base.latitude != info.latitude ||
        base.longitude != info.longitude ||
        base.imageAsset != info.imageAsset)
      throw const FormatException('门店标识或定位不能修改');
    if (info.name.trim().runes.length < 2 ||
        info.name.runes.length > 40 ||
        description.runes.length > 500 ||
        (!RegExp(r'^[0-9+()\- ]{7,20}$').hasMatch(info.phone) ||
            info.phone.replaceAll(RegExp(r'\D'), '').length < 7))
      throw const FormatException('请检查名称、电话和介绍长度');
    if (info.imageBytes != null &&
        (info.imageBytes!.isEmpty || info.imageBytes!.length > 256 * 1024))
      throw const FormatException('图片不能超过256KiB');
    if (revision < 0 ||
        openMinute < 0 ||
        closeMinute > 1410 ||
        openMinute >= closeMinute ||
        openMinute % 30 != 0 ||
        closeMinute % 30 != 0)
      throw const FormatException('营业时段需为当天半小时整点，起点早于终点');
    for (final key in closedDates) {
      final date = DateTime.tryParse(key);
      if (date == null || storeDateKey(date) != key)
        throw const FormatException('休息日期无效');
    }
    final expected = <String>{
      for (final service in demoServicePrices.entries)
        for (final section in service.value.entries)
          for (final choice in section.value.keys)
            '${service.key}:${section.key}:$choice',
    };
    if (items.length != expected.length ||
        items.map((i) => i.key).toSet().length != expected.length ||
        items.any((i) => !expected.contains(i.key)))
      throw const FormatException('服务项目集合无效');
    for (final item in items) {
      validateMoney(item.cents);
      if (item.section == 1 && item.cents == 0)
        throw const FormatException('套餐价格必须大于零');
    }
    for (final service in demoServicePrices.keys) {
      for (final section in [1, 2]) {
        if (!items.any(
          (i) => i.service == service && i.section == section && i.enabled,
        ))
          throw const FormatException('必选套餐和用品不能全部下架');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'description': description,
    'acceptingBookings': acceptingBookings,
    'openMinute': openMinute,
    'closeMinute': closeMinute,
    'revision': revision,
    'closedDates': closedDates.toList()..sort(),
    'items': items.map((i) => i.toJson()).toList(),
  };
  factory StoreSettings.fromJson(Map<String, dynamic> data) {
    if (data['info'] is! Map<String, dynamic> ||
        data['description'] is! String ||
        data['acceptingBookings'] is! bool ||
        data['openMinute'] is! int ||
        data['closeMinute'] is! int ||
        data['revision'] is! int ||
        data['closedDates'] is! List ||
        (data['closedDates'] as List).any((v) => v is! String) ||
        data['items'] is! List ||
        (data['items'] as List).any((v) => v is! Map<String, dynamic>))
      throw const FormatException('门店设置损坏');
    return StoreSettings(
      info: StoreInfo.fromJson(data['info']),
      description: data['description'],
      acceptingBookings: data['acceptingBookings'],
      openMinute: data['openMinute'],
      closeMinute: data['closeMinute'],
      revision: data['revision'],
      closedDates: (data['closedDates'] as List).cast<String>().toSet(),
      items: (data['items'] as List)
          .map((v) => StoreServiceItem.fromJson(v))
          .toList(),
    );
  }
}
