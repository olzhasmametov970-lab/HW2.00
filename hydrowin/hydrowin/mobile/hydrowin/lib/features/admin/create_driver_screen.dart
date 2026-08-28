import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/user_roles.dart';

/// Админ завода или платформы: создать учётку водителя и привязать к машине.
class CreateDriverScreen extends StatefulWidget {
  const CreateDriverScreen({super.key});

  @override
  State<CreateDriverScreen> createState() => _CreateDriverScreenState();
}

class _CreateDriverScreenState extends State<CreateDriverScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  List<MachineSummary> _machines = const [];
  String? _machineId;
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
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!UserRoles.canCreateDriver(
        isAdmin: admin,
        isClientOrg: me.isClient,
        isPlatformOrg: me.isPlatform,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Доступно администратору завода или платформы',
            ),
          ),
        );
        context.pop();
        return;
      }

      final fleet = await scope.machines.listMachines();
      if (!mounted) return;
      setState(() {
        _allowed = true;
        _machines = fleet.items;
        _machineId = fleet.items.isNotEmpty ? fleet.items.first.id : null;
      });
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (_machineId == null) {
      setState(() => _error = 'Сначала зарегистрируйте машину на заводе');
      return;
    }
    if (name.length < 2 || email.isEmpty || password.length < 8) {
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
      final created = await CloudScope.of(context).organizations.createUser(
        name: name,
        email: email,
        password: password,
        role: UserRoles.driver,
        assignedMachineId: _machineId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Водитель «${created.name}» создан · машина привязана',
          ),
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = auth.humanizeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Создать водителя')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Учётка завода с доступом только к одной выбранной машине. '
            'Водитель появится в организации владельца машины.',
            style: TextStyle(height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Имя',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email (логин)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
              helperText: 'Не короче 8 символов, буквы и цифры',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _machineId,
            decoration: const InputDecoration(
              labelText: 'Машина',
              border: OutlineInputBorder(),
            ),
            items: _machines
                .map(
                  (m) => DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      [
                        if (m.ownerOrgName != null && m.ownerOrgName!.isNotEmpty)
                          m.ownerOrgName!,
                        '${m.code} · ${m.name}',
                      ].join(' · '),
                    ),
                  ),
                )
                .toList(),
            onChanged: _machines.isEmpty
                ? null
                : (v) => setState(() => _machineId = v),
          ),
          if (_machines.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Нет машин в парке. Сначала зарегистрируйте плату.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading || _machines.isEmpty ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать водителя'),
          ),
        ],
      ),
    );
  }
}
