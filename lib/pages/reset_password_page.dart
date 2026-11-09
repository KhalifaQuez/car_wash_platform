import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/demo_account_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_notice.dart';

/// 本地演示页面：显示测试验证码，不发送真实短信。
class ResetPasswordPage extends StatefulWidget {
  final DemoAccountStore store;
  final String initialPhone;

  const ResetPasswordPage({
    super.key,
    required this.store,
    this.initialPhone = '',
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneFieldKey = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _phoneController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  DemoPasswordResetCode? _challenge;
  Timer? _countdown;
  bool _obscurePassword = true;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone.trim());
    if (_retrySeconds > 0) _startCountdown();
  }

  int get _retrySeconds =>
      (widget.store
                  .passwordResetRetryAfter(_phoneController.text)
                  .inMilliseconds /
              1000)
          .ceil();

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_challenge == null && _retrySeconds == 0) timer.cancel();
      setState(() {});
    });
  }

  void _phoneChanged(String value) {
    setState(() {
      if (_challenge != null && value.trim() != _challenge!.phone) {
        _challenge = null;
        _codeController.clear();
      }
    });
    if (_retrySeconds > 0 && _countdown?.isActive != true) {
      _startCountdown();
    }
  }

  void _getCode() {
    if (_saved || _saving || _retrySeconds > 0) return;
    if (!_phoneFieldKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    try {
      final challenge = widget.store.requestPasswordResetCode(
        phone: _phoneController.text,
      );
      setState(() {
        _challenge = challenge;
        _codeController.clear();
      });
      _startCountdown();
      AppNotice.show(context, '演示验证码已生成，请查看页面上的验证码');
    } on AccountValidationException catch (error) {
      AppNotice.show(context, error.message);
    }
  }

  Future<void> _resetPassword() async {
    if (_saved || _saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final phone = _phoneController.text.trim();
      await widget.store.resetPassword(
        phone: phone,
        code: _codeController.text,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });
      _countdown?.cancel();
      AppNotice.show(context, '密码已重置，请使用新密码登录');
      Navigator.of(context).pop<String>(phone);
    } on AccountValidationException catch (error) {
      if (!mounted) return;
      if (!widget.store.hasActivePasswordResetCode(_phoneController.text)) {
        setState(() => _challenge = null);
      }
      AppNotice.show(context, error.message);
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: const Color(0xE6111A2B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _codeCard(DemoPasswordResetCode challenge) {
    final seconds =
        (challenge.expiresAt.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 300)
            .toInt();
    final validity =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xE6231836),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.purpleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '演示验证码（未发送短信）',
            style: TextStyle(color: AppPalette.lightPurple, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text(
            seconds > 0 ? challenge.code : '验证码已过期',
            style: TextStyle(
              color: AppPalette.lightText,
              fontSize: seconds > 0 ? 28 : 18,
              fontWeight: FontWeight.w600,
              letterSpacing: seconds > 0 ? 8 : 0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            seconds > 0
                ? '手机号：${challenge.phone}\n剩余有效期：$validity'
                : '请重新获取验证码。',
            style: const TextStyle(
              color: AppPalette.lightText,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final retrySeconds = _retrySeconds;
    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('重置密码'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                children: [
                  const Text(
                    '重新设置密码',
                    style: TextStyle(
                      color: AppPalette.lightText,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xE6231836),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '本地演示模式，不发送真实短信。\n'
                      '请输入已在本机注册的手机号，测试验证码会显示在下方。\n'
                      '验证码有效期 5 分钟，60 秒后可重新获取。',
                      style: TextStyle(
                        color: AppPalette.lightText,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    key: _phoneFieldKey,
                    controller: _phoneController,
                    enabled: !_saved,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    maxLength: 11,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration('已注册手机号', Icons.phone_outlined),
                    validator: validatePhone,
                    onChanged: _phoneChanged,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _saved || retrySeconds > 0 ? null : _getCode,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(
                      retrySeconds > 0 ? '$retrySeconds 秒后可重新获取' : '获取演示验证码',
                    ),
                  ),
                  if (_challenge != null) ...[
                    const SizedBox(height: 16),
                    _codeCard(_challenge!),
                  ],
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _codeController,
                    enabled: !_saved,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(
                      '6 位验证码',
                      Icons.verified_user_outlined,
                    ),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch((value ?? '').trim())
                        ? null
                        : '请输入 6 位数字验证码',
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_saved,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      '新密码',
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: _saved
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _confirmController,
                    enabled: !_saved,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    decoration: _decoration('确认新密码', Icons.lock_outline),
                    validator: (value) =>
                        value == _passwordController.text ? null : '两次输入的密码不一致',
                    onFieldSubmitted: (_) => _resetPassword(),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saved ? null : _resetPassword,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(_saving ? '正在保存…' : '重置密码并返回登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
