import 'service_option_data.dart';

/// 全部是可配置的演示价格，单位为分；不是门店真实报价。
const demoServicePrices = <String, Map<int, Map<String, int>>>{
  '洗车': {
    1: {'标准外观清洗': 3900, '精细内外清洗': 7900, '深度清洁护理': 12900},
    2: {'中性清洗液': 0, '高泡清洗液': 1000, '环保低泡清洗液': 1500},
    3: {'内饰重点清洁': 1500, '轮毂重点清洁': 1000, '宠物毛发处理': 2500},
  },
  '保养': {
    1: {'基础保养': 19900, '常规综合保养': 39900, '全面检查养护': 69900},
    2: {'机油': 12000, '防冻液': 6000, '制动液': 4500, '变速箱油': 8000},
    3: {'检查异响': 3000, '检查轮胎': 2000, '检查刹车': 2500},
  },
};

String priceMoney(int cents) => '¥${(cents / 100).toStringAsFixed(2)}';
int? demoChoicePrice(String service, int section, String choice) =>
    demoServicePrices[service]?[section]?[choice];

class ServicePriceLine {
  final int section;
  final String label;
  final int cents;
  const ServicePriceLine(this.section, this.label, this.cents);
  Map<String, dynamic> toJson() => {
    'section': section,
    'label': label,
    'cents': cents,
  };
  factory ServicePriceLine.fromJson(Map<String, dynamic> data) {
    if (data['section'] is! int ||
        data['label'] is! String ||
        data['cents'] is! int ||
        (data['section'] as int) < 0 ||
        (data['section'] as int) > 3 ||
        (data['label'] as String).isEmpty ||
        (data['cents'] as int) < 0) {
      throw const FormatException('Invalid price line');
    }
    return ServicePriceLine(
      data['section'] as int,
      data['label'] as String,
      data['cents'] as int,
    );
  }
}

/// 尚未填完整也能报价，方便实时显示；提交仍需验证完整服务与时间。
List<ServicePriceLine> quoteServiceSelections(
  String service,
  List<ServiceOptionSelection?> selections,
) {
  if (serviceOptionsFor(service).length != 4 || selections.length != 4) {
    throw const FormatException('Unknown service quote');
  }
  return List.unmodifiable([
    if (selections[0]?.appointment != null)
      const ServicePriceLine(0, '预约到店时间', 0),
    for (var index = 1; index < 4; index++)
      for (final choice in selections[index]?.choices ?? <String>{})
        ServicePriceLine(
          index,
          choice,
          demoChoicePrice(service, index, choice) ??
              (throw const FormatException('Price is not configured')),
        ),
    if (selections[3]?.note.trim().isNotEmpty == true)
      const ServicePriceLine(3, '文字备注', 0),
  ]);
}

int priceTotal(Iterable<ServicePriceLine> lines) =>
    lines.fold(0, (total, line) => total + line.cents);
int priceForSection(Iterable<ServicePriceLine> lines, int section) =>
    priceTotal(lines.where((line) => line.section == section));
