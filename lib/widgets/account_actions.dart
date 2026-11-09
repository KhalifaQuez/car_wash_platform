import 'package:flutter/material.dart';
import '../models/demo_account_store.dart';
import 'app_notice.dart';
import 'app_background.dart';
import '../pages/reset_password_page.dart';

class AccountActions extends StatelessWidget {
  final DemoAccountStore store;
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final bool busy;

  const AccountActions({
    super.key,
    required this.store,
    required this.onRegister,
    required this.onLogin,
    required this.onLogout,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final outlineStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: shape,
    );
    if (store.currentUser != null) {
      return SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: busy ? null : onLogout,
          icon: const Icon(Icons.logout, size: 19),
          label: const Text('退出登录'),
          style: outlineStyle,
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onRegister,
              style: outlineStyle,
              child: const Text('注册'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : onLogin,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: shape,
              ),
              child: const Text(
                '登录',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatefulWidget {
  final bool register;
  final DemoAccountStore store;
  final Duration enterDuration;
  final Duration returnDuration;

  const AccountPage({
    super.key,
    required this.register,
    required this.store,
    this.enterDuration = const Duration(milliseconds: 1200),
    this.returnDuration = const Duration(milliseconds: 1000),
  });
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late bool _register;
  bool _submitted = false;
  bool _openingReset = false;
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _savingRemember = false;
  late bool _rememberMe;

  bool get _busy =>
      _submitted || _openingReset || _submitting || _savingRemember;

  @override
  void initState() {
    super.initState();
    _register = widget.register;
    _rememberMe = widget.store.rememberedPhone != null;
    if (!_register) {
      _phoneController.text = widget.store.rememberedPhone ?? '';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      if (_register) {
        await widget.store.register(
          username: _usernameController.text,
          phone: _phoneController.text,
          password: _passwordController.text,
          rememberPhone: _rememberMe,
        );
      } else {
        await widget.store.login(
          phone: _phoneController.text,
          password: _passwordController.text,
          rememberPhone: _rememberMe,
        );
      }
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      // 注册成功后也自动登录。
      Navigator.of(context).pop(true);
    } on AccountValidationException catch (error) {
      if (mounted) AppNotice.show(context, error.message);
    } finally {
      if (mounted && !_submitted) setState(() => _submitting = false);
    }
  }

  Future<void> _changeRememberMe(bool? value) async {
    if (_busy || value == null) return;
    if (value) {
      setState(() => _rememberMe = true);
      return;
    }
    // 取消勾选立即清除旧记忆，即使之后直接关闭或返回也会生效。
    setState(() => _savingRemember = true);
    try {
      await widget.store.clearRememberedPhone();
      if (mounted) setState(() => _rememberMe = false);
    } on AccountValidationException catch (error) {
      if (mounted) AppNotice.show(context, error.message);
    } finally {
      if (mounted) setState(() => _savingRemember = false);
    }
  }

  Future<void> _openForgotPassword() async {
    if (_busy || _register) return;
    if (_phoneController.text.trim() == demoAdminPhone) {
      AppNotice.show(context, '演示管理员账号不支持短信重置密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _openingReset = true);
    try {
      final route = PageRouteBuilder<String>(
        transitionDuration: widget.enterDuration,
        reverseTransitionDuration: widget.returnDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ResetPasswordPage(
              store: widget.store,
              initialPhone: _phoneController.text,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = animation.drive(
            CurveTween(curve: Curves.easeInOutCubic),
          );
          return FadeTransition(
            opacity: curved,
            child: AppBackground(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
      final resetPhone = await Navigator.of(context).push<String>(route);
      await route.completed;
      if (!mounted) return;
      if (resetPhone != null) {
        _phoneController.text = resetPhone;
        _passwordController.clear();
        _confirmController.clear();
      }
    } finally {
      if (mounted) setState(() => _openingReset = false);
    }
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
      filled: true,
      fillColor: const Color(0xFF111A2B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting && !_savingRemember,
      child: AbsorbPointer(
        absorbing: _submitting || _savingRemember,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(_register ? '注册' : '登录'),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                children: [
                  Text(
                    _register ? '开启爱车的新旅程' : '欢迎回来',
                    style: const TextStyle(
                      color: Color(0xFFEAF1FF),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A fresh ride. A fresh start.',
                    style: TextStyle(
                      color: Color(0xFF93A4BE),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 36),
                  if (_register) ...[
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      maxLength: 20,
                      decoration: _decoration('用户名', Icons.person_outline),
                      validator: validateUsername,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('手机号', Icons.phone_outlined),
                    validator: _register
                        ? validateRegistrationPhone
                        : validateLoginPhone,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: _register
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: _decoration(
                      '密码',
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(
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
                    onFieldSubmitted: (_) {
                      if (!_register) _submit();
                    },
                  ),
                  if (!_register)
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: '只记住手机号，不保存密码或自动登录',
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: _busy ? null : _changeRememberMe,
                                ),
                                Flexible(
                                  child: InkWell(
                                    onTap: _busy
                                        ? null
                                        : () => _changeRememberMe(!_rememberMe),
                                    child: const Text('记住我'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _openForgotPassword,
                          child: const Text('忘记密码？'),
                        ),
                      ],
                    ),
                  if (_register) ...[
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      decoration: _decoration('确认密码', Icons.lock_outline),
                      validator: (value) {
                        return value != _passwordController.text
                            ? '两次输入的密码不一致'
                            : null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _submitting ? '正在保存…' : (_register ? '注册并登录' : '登录'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _register = !_register;
                              _confirmController.clear();
                            });
                          },
                    child: Text(_register ? '已有账户？去登录' : '还没有账户？去注册'),
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
