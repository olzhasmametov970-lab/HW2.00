import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';

/// Только админ платформы: создать производителя и его администратора.
class CreateManufacturerScreen extends StatefulWidget {
  const CreateManufacturerScreen({super.key});

  @override
  State<CreateManufacturerScreen> createState() =>
      _CreateManufacturerScreenState();
}

class _CreateManufacturerScreenState extends State<CreateManufacturerScreen> {
  final _name = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  bool _loading = false;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guard());
  }

  @override
  void dispose() {
    _name.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _guard() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!me.isPlatform || !admin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Доступно только администратору платформы'),
          ),
        );
        context.pop();
        return;
      }
      setState(() => _allowed = true);
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final adminName = _adminName.text.trim();
    final email = _adminEmail.text.trim();
    final password = _adminPassword.text;
    if (name.length < 2 ||
        adminName.length < 2 ||
        email.isEmpty ||
        password.length < 8) {
      setState(
        () => _error =
            'Заполните все поля. Пароль: от 8 символов, буквы и цифры',
      );
      return;
    }
    final hasLetter = RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    if (!hasLetter || !hasDigit) {
      setState(
        () => _error = 'Пароль должен содержать буквы и цифры (например Kam12345)',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = CloudScope.of(context).auth;
    try {
      final created = await CloudScope.of(context).organizations
          .createManufacturer(
            name: name,
            adminName: adminName,
            adminEmail: email,
            adminPassword: password,
          );
      if (!mounted) return;
      final orgName =
          (created['organization'] as Map<String, dynamic>?)?['name'] ?? name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Производитель «$orgName» создан')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = auth.humanizeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Создать производителя')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Будет создана организация-производитель и учётная запись её администратора.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название производителя',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminName,
            decoration: const InputDecoration(
              labelText: 'Имя администратора',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email администратора',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Пароль администратора',
              border: OutlineInputBorder(),
              helperText: 'Не короче 8 символов, буквы и цифры (например Kam12345)',
            ),
            enabled: !_loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать производителя'),
          ),
        ],
      ),
    );
  }
}
