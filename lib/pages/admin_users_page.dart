import 'package:flutter/material.dart';
import '../models/activity_log_filter.dart';
import '../models/demo_account_store.dart';
import '../widgets/app_notice.dart';
import '../widgets/booking_dialogs.dart';
import 'booking_list_page.dart';
import 'admin_wallet_page.dart';
import 'finance_route.dart';

class AdminUsersPage extends StatefulWidget {
  final DemoAccountStore accountStore;
  final bool active;
  final Duration enterDuration;
  final Duration returnDuration;
  final Duration scrollDuration;
  const AdminUsersPage({
    super.key,
    required this.accountStore,
    required this.active,
    required this.enterDuration,
    required this.returnDuration,
    required this.scrollDuration,
  });
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  bool _busy = false;
  bool _logs = false;
  ActivityLogScope _logScope = ActivityLogScope.all;
  @override
  void initState() {
    super.initState();
    widget.accountStore.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.accountStore.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _bookings([String? userId]) async {
    if (_busy || !widget.active) return;
    setState(() => _busy = true);
    try {
      final route = PageRouteBuilder<void>(
        transitionDuration: widget.enterDuration,
        reverseTransitionDuration: widget.returnDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) => BookingListPage(
                accountStore: widget.accountStore,
                ownerId: userId,
                active: animation.value >= 1,
                enterDuration: widget.enterDuration,
                returnDuration: widget.returnDuration,
                scrollDuration: widget.scrollDuration,
              ),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: animation.drive(
                CurveTween(curve: Curves.easeInOutCubic),
              ),
              child: child,
            ),
      );
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } catch (error) {
      if (mounted) AppNotice.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(UserProfile user) async {
    if (_busy || !widget.active) return;
    setState(() => _busy = true);
    try {
      final result = await showBookingPopup<Map<String, String>>(
        context,
        (context) => _EditUserDialog(user: user),
        widget.enterDuration,
        widget.returnDuration,
      );
      if (result == null || !mounted) return;
      await widget.accountStore.adminUpdateUser(
        userId: user.id,
        username: result['username']!,
        phone: result['phone']!,
      );
      if (mounted) AppNotice.show(context, '用户资料已保存，原预约仍归属此账号');
    } catch (error) {
      if (mounted) AppNotice.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(UserProfile user) async {
    if (_busy || !widget.active) return;
    setState(() => _busy = true);
    try {
      final agreed = await confirmBookingAction(
        context,
        title: user.enabled ? '停用用户' : '启用用户',
        message: user.enabled
            ? '停用后此用户不能登录或提交新预约，原有预约与记录仍保留，管理员仍可处理。'
            : '启用后此用户可以继续登录和管理自己的预约。',
        confirmLabel: user.enabled ? '确认停用' : '确认启用',
        enterDuration: widget.enterDuration,
        returnDuration: widget.returnDuration,
      );
      if (!agreed || !mounted) return;
      await widget.accountStore.setUserEnabled(user.id, !user.enabled);
      if (mounted) AppNotice.show(context, user.enabled ? '用户已停用' : '用户已启用');
    } catch (error) {
      if (mounted) AppNotice.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.accountStore.isAdministrator) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1020),
        body: SafeArea(child: Center(child: Text('仅管理员可查看用户管理'))),
      );
    }
    final users = widget.accountStore.registeredUsers;
    final bookings = widget.accountStore.visibleBookings();
    final allEvents = widget.accountStore.activities;
    final administratorId = widget.accountStore.currentUser!.id;
    final events = filterActivityLogs(
      allEvents,
      _logScope,
      administratorId: administratorId,
    );
    final names = {
      for (final user in users) user.id: '${user.username} · ${user.phone}',
      'administrator:demo': '管理员',
      'guest': '未登录操作',
    };
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0B1020),
          image: DecorationImage(
            image: AssetImage('assets/images/store_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    const BackButton(),
                    const Expanded(
                      child: Text(
                        '用户管理',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${users.length} 位用户',
                      style: const TextStyle(color: Color(0xFFD2C4E3)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('用户资料'),
                      selected: !_logs,
                      onSelected: _busy || !widget.active
                          ? null
                          : (_) => setState(() => _logs = false),
                    ),
                    ChoiceChip(
                      label: const Text('操作记录'),
                      selected: _logs,
                      onSelected: _busy || !widget.active
                          ? null
                          : (_) => setState(() => _logs = true),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy || !widget.active
                          ? null
                          : () => _bookings(),
                      child: Text('全部预约（${bookings.length}）'),
                    ),
                  ],
                ),
              ),
              if (_logs)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final scope in ActivityLogScope.values)
                        ChoiceChip(
                          key: ValueKey('activity-scope-${scope.name}'),
                          label: Text(
                            '${switch (scope) {
                              ActivityLogScope.all => '全部记录',
                              ActivityLogScope.customer => '用户操作',
                              ActivityLogScope.administrator => '管理员操作',
                            }}（${filterActivityLogs(allEvents, scope, administratorId: administratorId).length}）',
                          ),
                          selected: _logScope == scope,
                          onSelected: _busy || !widget.active
                              ? null
                              : (_) => setState(() => _logScope = scope),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _logs
                    ? AnimatedSwitcher(
                        duration: widget.enterDuration,
                        reverseDuration: widget.returnDuration,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        child: events.isEmpty
                            ? Center(
                                key: ValueKey(
                                  'activity-empty-${_logScope.name}',
                                ),
                                child: Text(switch (_logScope) {
                                  ActivityLogScope.all => '暂无操作记录',
                                  ActivityLogScope.customer => '暂无用户操作记录',
                                  ActivityLogScope.administrator => '暂无管理员操作记录',
                                }),
                              )
                            : ListView.builder(
                                key: ValueKey(
                                  'activity-list-${_logScope.name}',
                                ),
                                padding: const EdgeInsets.all(18),
                                itemCount: events.length,
                                itemBuilder: (context, index) {
                                  final event = events[index];
                                  final date = event.at;
                                  return Card(
                                    color: const Color(0xDD281B37),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            event.action,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '操作对象：${names[event.targetUserId] ?? event.targetUserId}',
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '操作人：${names[event.actorId] ?? event.actorId}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFD2C4E3),
                                            ),
                                          ),
                                          if (event.detail.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              event.detail,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            '${date.year}/${date.month}/${date.day} '
                                            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFBBAACD),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      )
                    : users.isEmpty
                    ? const Center(child: Text('本机还没有注册用户'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(18),
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final count = bookings
                              .where((booking) => booking.ownerId == user.id)
                              .length;
                          return Card(
                            color: const Color(0xDD281B37),
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: const Color(
                                          0xFF584172,
                                        ),
                                        backgroundImage:
                                            user.avatarBytes == null
                                            ? null
                                            : MemoryImage(user.avatarBytes!),
                                        child: user.avatarBytes == null
                                            ? const Icon(Icons.person_outline)
                                            : null,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              user.username,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(user.phone),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        user.enabled ? '正常' : '已停用',
                                        style: const TextStyle(
                                          color: Color(0xFFD2C4E3),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: _busy || !widget.active
                                            ? null
                                            : () => _bookings(user.id),
                                        child: Text('查看预约（$count）'),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: _busy || !widget.active
                                            ? null
                                            : () => openFinancePage<void>(
                                                context,
                                                AdminWalletPage(
                                                  accountStore:
                                                      widget.accountStore,
                                                  userId: user.id,
                                                  enterDuration:
                                                      widget.enterDuration,
                                                  returnDuration:
                                                      widget.returnDuration,
                                                ),
                                                widget.enterDuration,
                                                widget.returnDuration,
                                              ),
                                        child: const Text('充值卡与流水'),
                                      ),
                                      OutlinedButton(
                                        onPressed: _busy || !widget.active
                                            ? null
                                            : () => _edit(user),
                                        child: const Text('修改资料'),
                                      ),
                                      OutlinedButton(
                                        onPressed: _busy || !widget.active
                                            ? null
                                            : () => _toggle(user),
                                        child: Text(
                                          user.enabled ? '停用用户' : '启用用户',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Text(
                  '仅管理同一台设备上的演示账号和预约，不是云端后台。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFFD2C4E3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final UserProfile user;
  const _EditUserDialog({required this.user});
  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.username);
    _phone = TextEditingController(text: widget.user.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_closing ||
        !_form.currentState!.validate() ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => _closing = true);
    Navigator.of(
      context,
    ).pop({'username': _name.text.trim(), 'phone': _phone.text.trim()});
  }

  @override
  Widget build(BuildContext context) => BookingPopupSurface(
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '修改用户资料',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            validator: validateUsername,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            validator: validateRegistrationPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '绑定手机号'),
          ),
          const SizedBox(height: 16),
          const Text(
            '账号身份不变，原有预约不会丢失。管理员无法查看用户密码。',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFD2C4E3),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _closing ? null : _save,
            child: const Text('保存资料'),
          ),
        ],
      ),
    ),
  );
}
