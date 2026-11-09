import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import '../models/demo_account_store.dart';
import '../widgets/user_profile_header.dart';
import '../widgets/app_notice.dart';

class ProfileEditPage extends StatefulWidget {
  final DemoAccountStore store;
  // 测试可注入选择器；实际 App 默认使用系统相册。
  final Future<Uint8List?> Function()? pickAvatar;
  const ProfileEditPage({super.key, required this.store, this.pickAvatar});
  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  Uint8List? _avatarBytes;
  bool _pickingPhoto = false;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.store.currentUser!;
    _usernameController = TextEditingController(text: user.username);
    _phoneController = TextEditingController(text: user.phone);
    _avatarBytes = user.avatarBytes;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppNotice.show(context, message);
  }

  Future<void> _chooseAvatar() async {
    if (_pickingPhoto || _saved) return;
    setState(() => _pickingPhoto = true);
    try {
      final bytes = widget.pickAvatar != null
          ? await widget.pickAvatar!()
          : await _readGalleryAvatar();
      if (bytes == null || !mounted) return;
      if (bytes.length > 3 * 1024 * 1024) {
        _showMessage('图片较大，请选择一张小于 3 MB 的头像');
        return;
      }
      setState(() => _avatarBytes = bytes);
    } on PlatformException {
      _showMessage('无法打开相册，请检查相册权限后重试');
    } catch (_) {
      _showMessage('读取图片失败，请重试；新增插件后需要完整重启 App');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<Uint8List?> _readGalleryAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return image == null ? null : await image.readAsBytes();
  }

  Future<void> _save() async {
    if (_pickingPhoto ||
        _saved ||
        _saving ||
        !_formKey.currentState!.validate())
      return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.store.updateProfile(
        username: _usernameController.text,
        phone: _phoneController.text,
        avatarBytes: _avatarBytes,
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });
      Navigator.of(context).pop(true);
    } on AccountValidationException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFF111A2B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('编辑个人资料'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                children: [
                  Center(
                    child: UserAvatar(
                      avatarBytes: _avatarBytes,
                      size: 104,
                      tooltip: '从相册更换头像',
                      onTap: _pickingPhoto || _saved ? null : _chooseAvatar,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickingPhoto || _saved ? null : _chooseAvatar,
                      icon: _pickingPhoto
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined, size: 19),
                      label: Text(_pickingPhoto ? '正在读取图片…' : '从相册更换头像'),
                    ),
                  ),
                  if (_avatarBytes != null)
                    Center(
                      child: TextButton(
                        onPressed: _pickingPhoto || _saved
                            ? null
                            : () => setState(() => _avatarBytes = null),
                        child: const Text('恢复默认头像'),
                      ),
                    ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    maxLength: 20,
                    decoration: _decoration('用户名', Icons.person_outline),
                    validator: validateUsername,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: _decoration(
                      '手机号',
                      Icons.phone_outlined,
                      helperText: '本地演示：修改后用新号码登录，暂不发送短信验证码。',
                    ),
                    validator: validatePhone,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _pickingPhoto || _saved ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(_saving ? '正在保存…' : '保存修改'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '返回不保存；点击“保存修改”后才更新首页资料。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF93A4BE), fontSize: 12),
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
