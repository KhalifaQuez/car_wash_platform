import 'dart:convert';
import 'dart:math';
import 'service_option_data.dart';
import 'store_info.dart';
import 'service_pricing.dart';
import 'recharge_data.dart';
import 'store_management_data.dart';

String newLocalId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

class BookingValidationException implements Exception {
  final String message;
  const BookingValidationException(this.message);
  @override
  String toString() => message;
}

enum BookingStatus { pendingPayment, paid, cancelled, completed }

String money(int cents) => '¥${(cents / 100).toStringAsFixed(2)}';

class BookingDraft {
  final String service;
  final List<ServiceOptionSelection> selections;
  BookingDraft(this.service, List<ServiceOptionSelection?> selections)
    : selections = List.unmodifiable([
        for (final selection in selections)
          selection ?? ServiceOptionSelection(),
      ]);

  DateTime get appointment => selections[0].appointment!;
  String get package => selections[1].choices.single;
  List<ServicePriceLine> get priceLines =>
      quoteServiceSelections(service, selections);
  int get amountCents => priceTotal(priceLines);

  void validate(
    DateTime now, {
    bool requireFuture = true,
    bool strictChoices = true,
    StoreSettings? settings,
  }) {
    final specs = serviceOptionsFor(service);
    if (specs.length != 4 || selections.length != 4) {
      throw const BookingValidationException('预约选项不完整');
    }
    final selectedTime = selections[0].appointment;
    if (selectedTime == null ||
        (requireFuture &&
            !(settings == null
                ? validDemoAppointment(selectedTime, now)
                : storeAppointmentSlots(
                    settings,
                    selectedTime,
                    now,
                  ).contains(selectedTime)))) {
      throw const BookingValidationException('请选择有效的未来到店日期和时间');
    }
    if ((selectedTime.minute != 0 && selectedTime.minute != 30) ||
        selectedTime.second != 0 ||
        selectedTime.millisecond != 0 ||
        selectedTime.microsecond != 0) {
      throw const BookingValidationException('预约时段格式无效');
    }
    if (selections[0].choices.isNotEmpty ||
        selections[0].note.isNotEmpty ||
        selections.skip(1).any((selection) => selection.appointment != null)) {
      throw const BookingValidationException('预约选项格式不正确');
    }
    for (var index = 1; index < 4; index++) {
      final selection = selections[index];
      if ((strictChoices &&
              selection.choices.any(
                (choice) => !specs[index].choices.contains(choice),
              )) ||
          selection.note.runes.length > 200 ||
          (index != 3 && selection.note.isNotEmpty)) {
        throw const BookingValidationException('服务选项无效，请重新选择');
      }
      if (index < 3 && selection.choices.isEmpty) {
        throw BookingValidationException('请完成${specs[index].title}');
      }
      if ((index == 1 || (index == 2 && service == '洗车')) &&
          selection.choices.length != 1) {
        throw const BookingValidationException('该选项需要单选');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'service': service,
    'selections': [
      for (final selection in selections)
        {
          'appointment': selection.appointment?.toIso8601String(),
          'choices': selection.choices.toList()..sort(),
          'note': selection.note,
        },
    ],
  };

  factory BookingDraft.fromJson(Map<String, dynamic> data) {
    final entries = data['selections'];
    if (data['service'] is! String || entries is! List || entries.length != 4) {
      throw const FormatException('Invalid booking draft');
    }
    final draft = BookingDraft(data['service'] as String, [
      for (final entry in entries) _selectionFromJson(entry),
    ]);
    draft.validate(DateTime.now(), requireFuture: false, strictChoices: false);
    return draft;
  }

  static ServiceOptionSelection _selectionFromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['choices'] is! List ||
        (value['choices'] as List).any((choice) => choice is! String) ||
        value['note'] is! String ||
        (value['appointment'] != null && value['appointment'] is! String)) {
      throw const FormatException('Invalid service selection');
    }
    return ServiceOptionSelection(
      appointment: value['appointment'] == null
          ? null
          : DateTime.parse(value['appointment'] as String),
      choices: (value['choices'] as List).cast<String>().toSet(),
      note: value['note'] as String,
    );
  }

  bool sameAs(BookingDraft other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

class Booking {
  final String id;
  final String requestId;
  final String ownerId;
  final StoreInfo store;
  final BookingDraft draft;
  final BookingStatus status;
  final int amountCents;
  final int netPaidCents;
  final int mockRefundedCents;
  final PaymentMethod? paymentMethod;
  final String? paymentCardId;
  final int lockedDiscountPercent;
  final int? _payableCents;
  int get payableCents => _payableCents ?? amountCents;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ServicePriceLine>? priceLines;
  final DateTime? customerDeletedAt;
  bool get hiddenFromCustomer => customerDeletedAt != null;

  /// 旧订单原来只有套餐价：其余项目按原规则零元，不使用新价重新计费。
  List<ServicePriceLine> get effectivePriceLines =>
      priceLines ??
      List.unmodifiable([
        const ServicePriceLine(0, '预约到店时间', 0),
        ServicePriceLine(1, draft.package, amountCents),
        for (var index = 2; index < 4; index++)
          for (final choice in draft.selections[index].choices)
            ServicePriceLine(index, choice, 0),
        if (draft.selections[3].note.isNotEmpty)
          const ServicePriceLine(3, '文字备注', 0),
      ]);
  const Booking({
    required this.id,
    required this.requestId,
    required this.ownerId,
    required this.store,
    required this.draft,
    required this.status,
    required this.amountCents,
    required this.netPaidCents,
    required this.mockRefundedCents,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.priceLines,
    this.customerDeletedAt,
    this.paymentMethod,
    this.paymentCardId,
    this.lockedDiscountPercent = 100,
    int? payableCents,
  }) : _payableCents = payableCents;

  int get balanceCents => max(0, payableCents - netPaidCents);
  bool get canEdit =>
      status == BookingStatus.pendingPayment || status == BookingStatus.paid;
  bool get canPay => status == BookingStatus.pendingPayment && balanceCents > 0;
  String get statusLabel => switch (status) {
    BookingStatus.pendingPayment => netPaidCents == 0 ? '待模拟支付' : '待模拟补差额',
    BookingStatus.paid => '已模拟支付',
    BookingStatus.cancelled => mockRefundedCents > 0 ? '已取消 · 模拟退款' : '已取消',
    BookingStatus.completed => '已模拟完成',
  };

  Booking copyWith({
    BookingDraft? draft,
    int? amountCents,
    BookingStatus? status,
    int? netPaidCents,
    int? mockRefundedCents,
    List<ServicePriceLine>? priceLines,
    PaymentMethod? paymentMethod,
    String? paymentCardId,
    int? lockedDiscountPercent,
    int? payableCents,
    DateTime? customerDeletedAt,
    required DateTime updatedAt,
  }) => Booking(
    id: id,
    requestId: requestId,
    ownerId: ownerId,
    store: store,
    draft: draft ?? this.draft,
    amountCents: amountCents ?? this.amountCents,
    status: status ?? this.status,
    netPaidCents: netPaidCents ?? this.netPaidCents,
    mockRefundedCents: mockRefundedCents ?? this.mockRefundedCents,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: updatedAt,
    priceLines: priceLines ?? this.priceLines,
    customerDeletedAt: customerDeletedAt ?? this.customerDeletedAt,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentCardId: paymentCardId ?? this.paymentCardId,
    lockedDiscountPercent: lockedDiscountPercent ?? this.lockedDiscountPercent,
    payableCents:
        payableCents ??
        (this.paymentMethod == null
            ? (amountCents ?? this.amountCents)
            : this.payableCents),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'requestId': requestId,
    'ownerId': ownerId,
    'draft': draft.toJson(),
    'status': status.name,
    'amountCents': amountCents,
    'netPaidCents': netPaidCents,
    'mockRefundedCents': mockRefundedCents,
    'paymentMethod': paymentMethod?.name,
    'paymentCardId': paymentCardId,
    'lockedDiscountPercent': lockedDiscountPercent,
    'payableCents': payableCents,
    'revision': revision,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'priceLines': effectivePriceLines.map((line) => line.toJson()).toList(),
    'customerDeletedAt': customerDeletedAt?.toIso8601String(),
    'store': store.toJson(),
  };

  factory Booking.fromJson(Map<String, dynamic> data) {
    final method = data['paymentMethod'] == null
        ? ((data['netPaidCents'] is int && data['netPaidCents'] > 0) ||
                  (data['mockRefundedCents'] is int &&
                      data['mockRefundedCents'] > 0)
              ? PaymentMethod.legacyMock
              : null)
        : PaymentMethod.values
              .where((m) => m.name == data['paymentMethod'])
              .firstOrNull;
    if ((data['paymentMethod'] != null && method == null) ||
        (data['paymentCardId'] != null && data['paymentCardId'] is! String) ||
        (data['lockedDiscountPercent'] != null &&
            data['lockedDiscountPercent'] is! int) ||
        (data['payableCents'] != null && data['payableCents'] is! int)) {
      throw const FormatException('Invalid payment snapshot');
    }
    final priceEntries = data['priceLines'];
    if ((priceEntries != null &&
            (priceEntries is! List ||
                priceEntries.any((entry) => entry is! Map<String, dynamic>))) ||
        (data['customerDeletedAt'] != null &&
            data['customerDeletedAt'] is! String)) {
      throw const FormatException('Invalid price or visibility data');
    }
    final shop = data['store'];
    if (data['amountCents'] is! int ||
        shop is! Map<String, dynamic> ||
        data['draft'] is! Map<String, dynamic> ||
        [
          'id',
          'requestId',
          'ownerId',
          'status',
          'createdAt',
          'updatedAt',
        ].any((key) => data[key] is! String) ||
        [
          'netPaidCents',
          'mockRefundedCents',
          'revision',
        ].any((key) => data[key] is! int) ||
        [
          'id',
          'name',
          'address',
          'referencePlace',
          'phone',
          'imageAsset',
        ].any((key) => shop[key] is! String) ||
        shop['latitude'] is! num ||
        shop['longitude'] is! num) {
      throw const FormatException('Invalid booking record');
    }
    final booking = Booking(
      id: data['id'] as String,
      requestId: data['requestId'] as String,
      ownerId: data['ownerId'] as String,
      store: StoreInfo.fromJson(shop),
      draft: BookingDraft.fromJson(data['draft'] as Map<String, dynamic>),
      status: BookingStatus.values.byName(data['status'] as String),
      amountCents: data['amountCents'] as int,
      netPaidCents: data['netPaidCents'] as int,
      mockRefundedCents: data['mockRefundedCents'] as int,
      paymentMethod: method,
      paymentCardId: data['paymentCardId'] as String?,
      lockedDiscountPercent: data['lockedDiscountPercent'] as int? ?? 100,
      payableCents: data['payableCents'] as int? ?? data['amountCents'] as int,
      revision: data['revision'] as int,
      createdAt: DateTime.parse(data['createdAt'] as String),
      updatedAt: DateTime.parse(data['updatedAt'] as String),
      priceLines: priceEntries == null
          ? null
          : List.unmodifiable(
              (priceEntries as List).map(
                (entry) =>
                    ServicePriceLine.fromJson(entry as Map<String, dynamic>),
              ),
            ),
      customerDeletedAt: data['customerDeletedAt'] == null
          ? null
          : DateTime.parse(data['customerDeletedAt'] as String),
    );
    validateMoney(booking.amountCents);
    validateMoney(booking.payableCents);
    validateMoney(booking.netPaidCents);
    validateMoney(booking.mockRefundedCents);
    if (booking.id.isEmpty ||
        booking.requestId.isEmpty ||
        booking.ownerId.isEmpty ||
        booking.revision < 1 ||
        booking.amountCents <= 0 ||
        (booking.priceLines != null &&
            priceTotal(booking.priceLines!) != booking.amountCents) ||
        booking.netPaidCents < 0 ||
        booking.mockRefundedCents < 0 ||
        booking.netPaidCents > booking.payableCents ||
        ![100, 95, 90, 85].contains(booking.lockedDiscountPercent) ||
        booking.payableCents !=
            (booking.amountCents * booking.lockedDiscountPercent + 50) ~/ 100 ||
        (booking.paymentMethod == PaymentMethod.rechargeCard &&
            (booking.paymentCardId == null ||
                booking.paymentCardId!.isEmpty ||
                booking.lockedDiscountPercent == 100)) ||
        (booking.paymentMethod != PaymentMethod.rechargeCard &&
            (booking.lockedDiscountPercent != 100 ||
                booking.paymentCardId != null)) ||
        ((booking.status == BookingStatus.paid ||
                booking.status == BookingStatus.completed) &&
            booking.netPaidCents != booking.payableCents) ||
        (booking.status == BookingStatus.cancelled &&
            booking.netPaidCents != 0) ||
        (booking.status == BookingStatus.pendingPayment &&
            booking.balanceCents == 0) ||
        !booking.store.latitude.isFinite ||
        !booking.store.longitude.isFinite ||
        booking.store.latitude.abs() > 90 ||
        booking.store.longitude.abs() > 180 ||
        !booking.store.imageAsset.startsWith('assets/images/')) {
      throw const FormatException('Invalid booking state');
    }
    return booking;
  }
}

class AccountActivity {
  final String id;
  final String actorId;
  final String targetUserId;
  final String action;
  final String detail;
  final String? bookingId;
  final DateTime at;
  const AccountActivity({
    required this.id,
    required this.actorId,
    required this.targetUserId,
    required this.action,
    required this.detail,
    required this.at,
    this.bookingId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'actorId': actorId,
    'targetUserId': targetUserId,
    'action': action,
    'detail': detail,
    'bookingId': bookingId,
    'at': at.toIso8601String(),
  };
  factory AccountActivity.fromJson(Map<String, dynamic> data) {
    if ([
          'id',
          'actorId',
          'targetUserId',
          'action',
          'detail',
          'at',
        ].any((key) => data[key] is! String) ||
        (data['bookingId'] != null && data['bookingId'] is! String)) {
      throw const FormatException('Invalid activity');
    }
    return AccountActivity(
      id: data['id'] as String,
      actorId: data['actorId'] as String,
      targetUserId: data['targetUserId'] as String,
      action: data['action'] as String,
      detail: data['detail'] as String,
      bookingId: data['bookingId'] as String?,
      at: DateTime.parse(data['at'] as String),
    );
  }
}
