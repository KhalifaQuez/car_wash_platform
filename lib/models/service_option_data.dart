/// 本阶段仅提供界面演示选项，不表示门店库存、价格或可预约时段。
enum ServiceOptionKind { appointment, package, supplies, requests }

class ServiceOptionSpec {
  final String title;
  final ServiceOptionKind kind;
  final List<String> choices;
  const ServiceOptionSpec(this.title, this.kind, [this.choices = const []]);
}

const washServiceOptions = <ServiceOptionSpec>[
  ServiceOptionSpec('预约到店时间', ServiceOptionKind.appointment),
  ServiceOptionSpec('洗车套餐选择', ServiceOptionKind.package, [
    '标准外观清洗',
    '精细内外清洗',
    '深度清洁护理',
  ]),
  ServiceOptionSpec('清洗液选择', ServiceOptionKind.supplies, [
    '中性清洗液',
    '高泡清洗液',
    '环保低泡清洗液',
  ]),
  ServiceOptionSpec('更多需求', ServiceOptionKind.requests, [
    '内饰重点清洁',
    '轮毂重点清洁',
    '宠物毛发处理',
  ]),
];

const careServiceOptions = <ServiceOptionSpec>[
  ServiceOptionSpec('预约到店时间', ServiceOptionKind.appointment),
  ServiceOptionSpec('保养套餐选择', ServiceOptionKind.package, [
    '基础保养',
    '常规综合保养',
    '全面检查养护',
  ]),
  ServiceOptionSpec('机油防冻液等选择', ServiceOptionKind.supplies, [
    '机油',
    '防冻液',
    '制动液',
    '变速箱油',
  ]),
  ServiceOptionSpec('更多需求', ServiceOptionKind.requests, [
    '检查异响',
    '检查轮胎',
    '检查刹车',
  ]),
];

List<ServiceOptionSpec> serviceOptionsFor(String service) => switch (service) {
  '洗车' => washServiceOptions,
  '保养' => careServiceOptions,
  _ => const [],
};

class ServiceOptionSelection {
  final DateTime? appointment;
  final Set<String> choices;
  final String note;
  ServiceOptionSelection({
    this.appointment,
    Set<String> choices = const {},
    this.note = '',
  }) : choices = Set.unmodifiable(choices);

  String get summary {
    if (appointment case final date?) {
      return '${date.month}月${date.day}日 '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
    final parts = [...choices, if (note.trim().isNotEmpty) note.trim()];
    return parts.isEmpty ? '暂不添加' : parts.join(' · ');
  }
}

List<DateTime> demoAppointmentDates(DateTime now) =>
    List.generate(7, (index) => DateTime(now.year, now.month, now.day + index));

/// 9:00～18:00 每半小时一个演示选项，剔除已过去的时间。
List<DateTime> demoAppointmentSlots(DateTime day, DateTime now) => [
  for (var minutes = 9 * 60; minutes <= 18 * 60; minutes += 30)
    if (DateTime(
      day.year,
      day.month,
      day.day,
      minutes ~/ 60,
      minutes % 60,
    ).isAfter(now))
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60),
];

bool validDemoAppointment(DateTime? value, DateTime now) {
  if (value == null || !value.isAfter(now)) return false;
  final dates = demoAppointmentDates(now);
  if (!dates.any(
    (day) =>
        day.year == value.year &&
        day.month == value.month &&
        day.day == value.day,
  )) {
    return false;
  }
  return demoAppointmentSlots(value, now).contains(value);
}

class ServiceSplitFrame {
  final double x;
  final double y;
  final double opacity;
  const ServiceSplitFrame(this.x, this.y, this.opacity);
}

double _phase(double time, double begin, double end) {
  final t = ((time - begin) / (end - begin)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 归一化轨迹：一个居中 -> 左右两个 -> 两行两列四个。
/// x/y = ±1 对应最终列/行中心，只有分裂后才显示子模块。
List<ServiceSplitFrame> serviceSplitFrames(double progress) {
  final time = progress.clamp(0.0, 1.0).toDouble();
  final birth = _phase(time, 0, 0.18);
  final horizontal = _phase(time, 0.18, 0.55);
  final vertical = _phase(time, 0.55, 1);
  return [
    ServiceSplitFrame(-horizontal, -vertical, birth),
    ServiceSplitFrame(horizontal, -vertical, birth * horizontal),
    ServiceSplitFrame(-horizontal, vertical, birth * vertical),
    ServiceSplitFrame(horizontal, vertical, birth * horizontal * vertical),
  ];
}
