import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/cloud_user.dart';
import 'package:intl/intl.dart';

/// Профиль текущего пользователя: фото и необязательные поля о себе.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _about = TextEditingController();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _newPassword2 = TextEditingController();

  CloudUser? _user;
  String _gender = '';
  DateTime? _birthDate;
  String? _avatarUrl;
  Uint8List? _pendingAvatarBytes;
  String? _pendingAvatarMime;
  bool _clearAvatar = false;
  bool _loading = true;
  bool _saving = false;
  bool _changingPassword = false;
  bool _obscurePasswords = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _about.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    _newPassword2.dispose();
    super.dispose();
  }

  String _mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = Uri.parse(CloudScope.of(context).api.baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    ).toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await CloudScope.of(context).organizations.fetchMyUser();
      if (!mounted) return;
      setState(() {
        _user = u;
        _firstName.text = u.firstName;
        _lastName.text = u.lastName;
        _phone.text = u.phone;
        _about.text = u.about;
        _gender = u.gender;
        _birthDate = u.birthDate != null && u.birthDate!.isNotEmpty
            ? DateTime.tryParse(u.birthDate!)
            : null;
        _avatarUrl = u.avatarUrl;
        _pendingAvatarBytes = null;
        _clearAvatar = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CloudScope.of(context).auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать файл')),
      );
      return;
    }
    if (bytes.length > 700000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото слишком большое (до ~500 КБ)')),
      );
      return;
    }
    final ext = (file.extension ?? 'jpg').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    setState(() {
      _pendingAvatarBytes = bytes;
      _pendingAvatarMime = mime;
      _clearAvatar = false;
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDate ?? DateTime(now.year - 30);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Дата рождения',
      cancelText: 'Очистить',
      confirmText: 'Выбрать',
    );
    // Если нажали вне диалога — null; отдельной кнопки «очистить» в DatePicker нет
    // на всех платформах, поэтому добавим действие ниже.
    if (!mounted) return;
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _changePassword() async {
    final oldP = _oldPassword.text;
    final newP = _newPassword.text;
    final newP2 = _newPassword2.text;
    if (oldP.isEmpty || newP.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите текущий и новый пароль')),
      );
      return;
    }
    if (newP != newP2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новый пароль и подтверждение не совпадают')),
      );
      return;
    }
    if (newP.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Новый пароль не короче 10 символов'),
        ),
      );
      return;
    }
    setState(() => _changingPassword = true);
    try {
      await CloudScope.of(context).auth.changePassword(
            oldPassword: oldP,
            newPassword: newP,
          );
      if (!mounted) return;
      _oldPassword.clear();
      _newPassword.clear();
      _newPassword2.clear();
      setState(() => _changingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль изменён')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _changingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? avatarB64;
      if (_pendingAvatarBytes != null && _pendingAvatarMime != null) {
        avatarB64 =
            'data:$_pendingAvatarMime;base64,${base64Encode(_pendingAvatarBytes!)}';
      }
      final orgs = CloudScope.of(context).organizations;
      final tokens = CloudScope.of(context).tokens;
      final updated = await orgs.updateMyProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        about: _about.text.trim(),
        gender: _gender,
        birthDate: _birthDate != null
            ? DateFormat('yyyy-MM-dd').format(_birthDate!)
            : '',
        avatarBase64: avatarB64,
        clearAvatar: _clearAvatar && avatarB64 == null,
      );
      await tokens.saveUserName(updated.name);
      if (!mounted) return;
      setState(() {
        _user = updated;
        _avatarUrl = updated.avatarUrl;
        _pendingAvatarBytes = null;
        _clearAvatar = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'Все поля необязательны — заполните то, что хотите.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: scheme.surfaceContainerHighest,
                            backgroundImage: _pendingAvatarBytes != null
                                ? MemoryImage(_pendingAvatarBytes!)
                                : (_avatarUrl != null && !_clearAvatar
                                    ? NetworkImage(_mediaUrl(_avatarUrl))
                                    : null),
                            child: (_pendingAvatarBytes == null &&
                                    (_avatarUrl == null || _clearAvatar))
                                ? Icon(
                                    Icons.person,
                                    size: 48,
                                    color: scheme.onSurfaceVariant,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _pickPhoto,
                                icon: const Icon(Icons.photo_outlined),
                                label: const Text('Фото'),
                              ),
                              if (_pendingAvatarBytes != null ||
                                  (_avatarUrl != null && !_clearAvatar))
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                            _pendingAvatarBytes = null;
                                            _clearAvatar = true;
                                          }),
                                  child: const Text('Убрать'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Имя',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Фамилия',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Дата рождения'),
                      subtitle: Text(
                        _birthDate == null
                            ? 'Не указана'
                            : DateFormat('dd.MM.yyyy').format(_birthDate!),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_birthDate != null)
                            IconButton(
                              tooltip: 'Очистить',
                              onPressed: () =>
                                  setState(() => _birthDate = null),
                              icon: const Icon(Icons.clear),
                            ),
                          IconButton(
                            onPressed: _pickBirthDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Пол', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '', label: Text('—')),
                        ButtonSegment(value: 'male', label: Text('Муж')),
                        ButtonSegment(value: 'female', label: Text('Жен')),
                        ButtonSegment(value: 'other', label: Text('Другое')),
                      ],
                      selected: {_gender},
                      onSelectionChanged: (s) {
                        if (s.isNotEmpty) setState(() => _gender = s.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон',
                        hintText: '+7 …',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _about,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'О себе',
                        alignLabelWithHint: true,
                        hintText: 'Должность, контакты, заметки…',
                      ),
                    ),
                    if (_user != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Email: ${_user!.email}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Смена пароля',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Укажите текущий пароль и новый (от 10 символов: '
                        'буква, цифра и спецсимвол).',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _oldPassword,
                        obscureText: _obscurePasswords,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Текущий пароль',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newPassword,
                        obscureText: _obscurePasswords,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Новый пароль',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newPassword2,
                        obscureText: _obscurePasswords,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Повторите новый пароль',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(
                            () => _obscurePasswords = !_obscurePasswords,
                          ),
                          icon: Icon(
                            _obscurePasswords
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          label: Text(
                            _obscurePasswords ? 'Показать' : 'Скрыть',
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FilledButton(
                        onPressed: _changingPassword || _saving
                            ? null
                            : _changePassword,
                        child: _changingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Сменить пароль'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
