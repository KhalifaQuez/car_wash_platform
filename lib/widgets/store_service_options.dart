import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../models/service_option_data.dart';
import '../models/service_pricing.dart';
import '../models/store_management_data.dart';
import '../models/booking_data.dart';

/// 服务选项编辑器；提交与本地保存由外层预约页面负责。
class StoreServiceOptions extends StatefulWidget {
  final StoreSettings settings;
  final Booking? existing;
  final String service;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  final List<ServiceOptionSelection?>? initialSelections;
  final ValueChanged<List<ServiceOptionSelection?>>? onChanged;
  final bool editable;
  final bool animateEntrance;
  final List<String>? priceTexts;
  const StoreServiceOptions({
    super.key,
    required this.settings,
    this.existing,
    required this.service,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
    this.initialSelections,
    this.onChanged,
    this.editable = true,
    this.animateEntrance = true,
    this.priceTexts,
  });

  @override
  State<StoreServiceOptions> createState() => _StoreServiceOptionsState();
}

class _StoreServiceOptionsState extends State<StoreServiceOptions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<ServiceOptionSelection?> _selections;
  bool _dialogOpen = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _selections = List.generate(
      4,
      (index) =>
          widget.initialSelections != null &&
              index < widget.initialSelections!.length
          ? widget.initialSelections![index]
          : null,
    );
    _controller = AnimationController(
      vsync: this,
      duration: widget.enterDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEntrance();
  }

  @override
  void didUpdateWidget(covariant StoreServiceOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.enterDuration;
    _syncEntrance();
  }

  void _syncEntrance() {
    if (!widget.active) {
      _controller.stop();
      return;
    }
    if (!widget.animateEntrance || MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _controller.value = 1;
    } else if (!_controller.isCompleted && !_controller.isAnimating) {
      _controller.forward(from: _started ? null : 0);
      _started = true;
    }
  }

  Future<void> _open(int index) async {
    if (_dialogOpen ||
        !widget.active ||
        !widget.editable ||
        !_controller.isCompleted) {
      return;
    }
    final options = serviceOptionsFor(widget.service);
    if (index >= options.length) return;
    setState(() => _dialogOpen = true);
    try {
      final route = _ServiceDialogRoute(
        enterDuration: widget.enterDuration,
        returnDuration: widget.returnDuration,
        builder: (context) => _ServiceOptionDialog(
          spec: ServiceOptionSpec(options[index].title, options[index].kind, [
            for (final choice in options[index].choices)
              if (widget.settings.item(widget.service, index, choice).enabled ||
                  widget.existing?.draft.selections[index].choices.contains(
                        choice,
                      ) ==
                      true)
                choice,
          ]),
          settings: widget.settings,
          existing: widget.existing,
          service: widget.service,
          initial: _selections[index],
        ),
      );
      final result = await Navigator.of(
        context,
      ).push<ServiceOptionSelection>(route);
      await route.completed;
      if (mounted && result != null) {
        setState(() => _selections[index] = result);
        widget.onChanged?.call(List.unmodifiable(_selections));
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = serviceOptionsFor(widget.service);
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '服务选项',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '点击模块选择',
          style: TextStyle(fontSize: 12, color: Color(0xFFC4B5D8)),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final side = math.max(0.0, (constraints.maxWidth - gap) / 2);
            final center = (side + gap) / 2;
            return SizedBox(
              height: side * 2 + gap,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final frames = serviceSplitFrames(_controller.value);
                  final enabled =
                      widget.active &&
                      widget.editable &&
                      _controller.isCompleted &&
                      !_dialogOpen;
                  return IgnorePointer(
                    ignoring: !enabled,
                    child: Stack(
                      children: [
                        for (var index = 0; index < 4; index++)
                          Positioned(
                            left: center + center * frames[index].x,
                            top: center + center * frames[index].y,
                            width: side,
                            height: side,
                            child: ExcludeSemantics(
                              excluding: !enabled,
                              child: Opacity(
                                opacity: frames[index].opacity,
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateX((1 - _controller.value) * 0.08)
                                    ..scaleByDouble(
                                      0.94 + 0.06 * _controller.value,
                                      0.94 + 0.06 * _controller.value,
                                      1,
                                      1,
                                    ),
                                  child: _ServiceSquare(
                                    key: ValueKey('service-option-$index'),
                                    index: index,
                                    title: options[index].title,
                                    selection: _selections[index],
                                    // 时间和更多需求卡片不显示价格；计价规则不变。
                                    priceText:
                                        options[index].kind ==
                                                ServiceOptionKind.package ||
                                            options[index].kind ==
                                                ServiceOptionKind.supplies
                                        ? widget.priceTexts != null
                                              ? widget.priceTexts![index]
                                              : _priceText(index)
                                        : null,
                                    onTap: () => _open(index),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  String _priceText(int index) {
    try {
      return '演示 ${priceMoney(priceForSection(quoteStoreSelections(widget.settings, widget.service, _selections, existing: widget.existing), index))}';
    } catch (_) {
      return '价格待确认';
    }
  }
}

class _ServiceSquare extends StatelessWidget {
  final int index;
  final String title;
  final ServiceOptionSelection? selection;
  final VoidCallback onTap;
  final String? priceText;
  const _ServiceSquare({
    super.key,
    required this.index,
    required this.title,
    required this.selection,
    required this.onTap,
    required this.priceText,
  });

  static const _icons = [
    Icons.schedule_outlined,
    Icons.auto_awesome_outlined,
    Icons.water_drop_outlined,
    Icons.tune_outlined,
  ];
  static const _colors = [
    Color(0xFF665084),
    Color(0xFF583E7A),
    Color(0xFF4D426E),
    Color(0xFF493556),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '$title，${selection?.summary ?? '点击选择'}'
        '${priceText == null ? '' : '，$priceText'}',
    child: Material(
      color: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x663D265C),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_colors[index], const Color(0xFF24182F)],
          ),
          border: Border.all(color: const Color(0x337E65A0)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _icons[index],
                          size: 30,
                          color: const Color(0xFFE4D3FF),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selection?.summary ?? '点击选择',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Color(0xFFD2C4E3),
                          ),
                        ),
                        if (priceText != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            priceText!,
                            key: ValueKey('service-price-$index'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF1E5FF),
                            ),
                          ),
                        ],
                        if (selection != null) ...[
                          const SizedBox(height: 6),
                          const Icon(
                            Icons.check_circle_outline,
                            size: 15,
                            color: Color(0xFFE4D3FF),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 轻量弹窗而非新整页，统一进入/关闭时长。
class _ServiceDialogRoute extends RawDialogRoute<ServiceOptionSelection> {
  final Duration returnDuration;
  _ServiceDialogRoute({
    required Duration enterDuration,
    required this.returnDuration,
    required WidgetBuilder builder,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         barrierDismissible: true,
         barrierLabel: '关闭服务选项',
         barrierColor: const Color(0x66000000),
         transitionDuration: enterDuration,
         transitionBuilder: (context, animation, secondaryAnimation, child) {
           final curved = animation.drive(
             CurveTween(curve: Curves.easeInOutCubic),
           );
           return FadeTransition(
             opacity: curved,
             child: SlideTransition(
               position: Tween<Offset>(
                 begin: const Offset(0, 0.06),
                 end: Offset.zero,
               ).animate(curved),
               child: ScaleTransition(
                 scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                 child: child,
               ),
             ),
           );
         },
       );
  @override
  Duration get reverseTransitionDuration => returnDuration;
}

class _ServiceOptionDialog extends StatefulWidget {
  final StoreSettings settings;
  final Booking? existing;
  final ServiceOptionSpec spec;
  final String service;
  final ServiceOptionSelection? initial;
  const _ServiceOptionDialog({
    required this.settings,
    this.existing,
    required this.spec,
    required this.service,
    this.initial,
  });
  @override
  State<_ServiceOptionDialog> createState() => _ServiceOptionDialogState();
}

class _ServiceOptionDialogState extends State<_ServiceOptionDialog> {
  late final TextEditingController _note;
  late final List<DateTime> _dates;
  late DateTime _day;
  DateTime? _appointment;
  late final Set<String> _choices;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dates = demoAppointmentDates(now);
    _appointment = _validAppointment(widget.initial?.appointment, now)
        ? widget.initial!.appointment
        : null;
    _day = _appointment == null
        ? _dates.first
        : DateTime(_appointment!.year, _appointment!.month, _appointment!.day);
    _choices = {...?widget.initial?.choices};
    _note = TextEditingController(text: widget.initial?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _multiple =>
      widget.spec.kind == ServiceOptionKind.requests ||
      (widget.spec.kind == ServiceOptionKind.supplies &&
          widget.service == '保养');

  void _finish([ServiceOptionSelection? selection]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => _closing = true);
    Navigator.of(context).pop(selection);
  }

  void _confirm() {
    if (_closing) return;
    if (widget.spec.kind == ServiceOptionKind.appointment &&
        !_validAppointment(_appointment, DateTime.now())) {
      setState(() => _error = '请选择尚未过去的到店日期和时间');
      return;
    }
    if ((widget.spec.kind == ServiceOptionKind.package ||
            widget.spec.kind == ServiceOptionKind.supplies) &&
        _choices.isEmpty) {
      setState(() => _error = '请至少选择一项');
      return;
    }
    _finish(
      ServiceOptionSelection(
        appointment: widget.spec.kind == ServiceOptionKind.appointment
            ? _appointment
            : null,
        choices: _choices,
        note: widget.spec.kind == ServiceOptionKind.requests
            ? _note.text.trim()
            : '',
      ),
    );
  }

  Widget _choice(
    String label,
    bool selected,
    ValueChanged<bool> onSelected, {
    bool multiple = false,
    int? priceCents,
    Key? key,
  }) {
    const style = TextStyle(color: Color(0xFFF2EAF9), fontSize: 13);
    const side = BorderSide(color: Color(0x446F588A));
    final content = Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: style),
        if (priceCents != null)
          Text(
            priceMoney(priceCents),
            style: const TextStyle(
              color: Color(0xFFE4D3FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
    if (multiple) {
      return FilterChip(
        key: key,
        label: content,
        selected: selected,
        onSelected: onSelected,
        selectedColor: const Color(0xFF715197),
        backgroundColor: const Color(0xFF2A2136),
        side: side,
        checkmarkColor: const Color(0xFFE4D3FF),
      );
    }
    return ChoiceChip(
      key: key,
      label: content,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      side: side,
      selectedColor: const Color(0xFF715197),
      backgroundColor: const Color(0xFF2A2136),
    );
  }

  Widget _appointmentBody() {
    final now = DateTime.now();
    final slots = storeAppointmentSlots(widget.settings, _day, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择日期',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (var index = 0; index < _dates.length; index++)
              _choice(
                '${_dates[index].month}/${_dates[index].day}${index == 0 ? ' 今天' : ''}',
                _dates[index] == _day,
                (_) => setState(() {
                  _day = _dates[index];
                  _appointment = null;
                  _error = null;
                }),
                key: ValueKey('appointment-date-$index'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '选择时间',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty)
          const Text(
            '今天暂无可选演示时段，请选择其他日期。',
            style: TextStyle(color: Color(0xFFD2C4E3)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final slot in slots)
                _choice(
                  '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}',
                  _appointment == slot,
                  (_) => setState(() {
                    _appointment = slot;
                    _error = null;
                  }),
                  key: ValueKey('appointment-slot-${slot.hour}-${slot.minute}'),
                ),
            ],
          ),
        const SizedBox(height: 16),
        const Text(
          '按该店设置展示到店时段，仍为本机演示，不代表真实可预约名额。',
          style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFFBBAACD)),
        ),
      ],
    );
  }

  Widget _choicesBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _multiple ? '可以选择多项' : '请选择一项',
        style: const TextStyle(color: Color(0xFFD2C4E3)),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice in widget.spec.choices)
            _choice(
              choice,
              _choices.contains(choice),
              (selected) => setState(() {
                if (!_multiple) _choices.clear();
                if (selected) {
                  _choices.add(choice);
                } else {
                  _choices.remove(choice);
                }
                _error = null;
              }),
              multiple: _multiple,
              priceCents: _choicePrice(choice),
            ),
        ],
      ),
      if (widget.spec.kind == ServiceOptionKind.requests) ...[
        const SizedBox(height: 20),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 5,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '其他需求（选填）',
            hintText: '写下你希望门店重点处理的问题',
            labelStyle: TextStyle(color: Color(0xFFD2C4E3)),
            hintStyle: TextStyle(color: Color(0xFFAA9DB8)),
            filled: true,
            fillColor: Color(0xFF251D31),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        widget.spec.kind == ServiceOptionKind.supplies && widget.service == '保养'
            ? '这里只记录用品类别。具体规格、车型适配和是否需要更换，需由门店人员确认。'
            : '以上均为演示价；预约时间及文字备注不收费，真实价格与服务范围需门店确认。',
        style: const TextStyle(
          fontSize: 12,
          height: 1.6,
          color: Color(0xFFBBAACD),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = math.max(
      0.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom - 48,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xF044315C), Color(0xF021192C)],
                ),
                border: Border.all(color: const Color(0x557E65A0)),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.spec.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: _finish,
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFFE4D3FF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      widget.spec.kind == ServiceOptionKind.appointment
                          ? _appointmentBody()
                          : _choicesBody(),
                      const SizedBox(height: 14),
                      Text(
                        _dialogPriceText(),
                        key: const ValueKey('service-dialog-subtotal'),
                        style: const TextStyle(
                          color: Color(0xFFF1E5FF),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFFB7CA),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _finish,
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _confirm,
                              child: const Text('确认选择'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _dialogPriceText() {
    var cents = 0;
    for (final choice in _choices) {
      final price = _choicePrice(choice);
      cents += price;
    }
    return '本项演示小计：${priceMoney(cents)}';
  }

  bool _validAppointment(DateTime? value, DateTime now) =>
      value != null &&
      storeAppointmentSlots(widget.settings, value, now).contains(value);
  int _choicePrice(String choice) =>
      widget.existing?.effectivePriceLines
          .where(
            (p) => p.section == widget.spec.kind.index && p.label == choice,
          )
          .firstOrNull
          ?.cents ??
      widget.settings
          .item(widget.service, widget.spec.kind.index, choice)
          .cents;
}
