import 'package:flutter/material.dart';
import '../models/recharge_data.dart';

class PaymentMethodSelector extends StatelessWidget {
  final List<PaymentMethod> methods;
  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onChanged;
  final bool enabled;
  const PaymentMethodSelector({
    super.key,
    required this.methods,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => RadioGroup<PaymentMethod>(
    groupValue: selected,
    onChanged: (value) {
      if (enabled && value != null) onChanged(value);
    },
    child: Column(
      children: [
        for (final method in methods)
          RadioListTile<PaymentMethod>(
            value: method,
            enabled: enabled,
            title: Text(method.label),
            secondary: Icon(switch (method) {
              PaymentMethod.bankCard => Icons.credit_card,
              PaymentMethod.wechat => Icons.chat_bubble_outline,
              PaymentMethod.alipay => Icons.account_balance_wallet_outlined,
              _ => Icons.wallet_outlined,
            }),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    ),
  );
}
