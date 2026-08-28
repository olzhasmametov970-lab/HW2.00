import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';

/// Производитель или админ платформы: создать завод и его администратора.
class CreateFactoryScreen extends StatefulWidget {
  const CreateFactoryScreen({super.key});

  @override
  State<CreateFactoryScreen> createState() => _CreateFactoryScreenState();
}

class _CreateFactoryScreenState extends State<CreateFactoryScreen> {
  final _name = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  List<ClientOrgSummary> _makers = const [];
  String? _makerId;
  bool _isPlatform = false;
  bool _loading = false;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAndLoad());
  }

  @override
  void dispose() {
    _name.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!admin || (!me.isPlatform && !me.isManufacturer)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Доступно администратору платформы или производителю',
            ),
          ),
        );
        context.pop();
        return;
      }

      if (me.isPlatform) {
        final makers = await scope.organizations.listManufacturers();
        if (!mounted) return;
        setState(() {
          _allowed = true;
          _isPlatform = true;
          _makers = makers;
          _makerId = makers.isNotEmpty ? makers.first.id : null;
        });
      } else {
        setState(() {
          _allowed = true;
          _isPlatform = false;
          _makerId = me.organization.id;
        });
      }
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final adminName = _adminName.text.trim();
    final email = _adminEmail.text.trim();
    final password = _adminPassword.text;
    if (_makerId == null) {
      setState(() => _error = 'Сначала создайте производителя');
      return;
    }
    if (name.length < 2 ||
        adminName.length < 2 ||
        email.isEmpty ||
        password.length < 8) {
      setState(
        () => _error = 'Заполните все поля (пароль не короче 8 символов)',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = CloudScope.of(context).auth;
    try {
      final created = await CloudScope.of(context).organizations.createClient(
        name: name,
        adminName: adminName,
        adminEmail: email,
        adminPassword: password,
        manufacturerOrganizationId: _isPlatform ? _makerId : null,
      );
      if (!mounted) return;
      final orgName =
          (created['organization'] as Map<String, dynamic>?)?['name'] ?? name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Завод «$orgName» создан')),
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
      appBar: AppBar(title: const Text('Создать завод')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _isPlatform
                ? 'Завод привязывается к производителю. Будет создан вход для администратора завода.'
                : 'Будет создана организация завода и учётная запись её администратора.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (_isPlatform) ...[
            if (_makers.isEmpty)
              const ListTile(
                leading: Icon(Icons.warning_amber),
                title: Text('Нет производителей'),
                subtitle: Text('Сначала создайте производителя'),
              )
            else
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _makerId,
                decoration: const InputDecoration(
                  labelText: 'Производитель',
                  border: OutlineInputBorder(),
                ),
                items: _makers
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _makerId = v),
              ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название завода',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adminName,
            decoration: const InputDecoration(
              labelText: 'Имя администратора завода',
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
              helperText: 'Не короче 8 символов, буквы и цифры',
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
            onPressed: _loading || (_isPlatform && _makers.isEmpty)
                ? null
                : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать завод'),
          ),
        ],
      ),
    );
  }
}
