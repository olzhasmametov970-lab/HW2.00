import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/user_roles.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAdmin = true;
  bool _isManufacturer = false;
  String? _roleLabel;
  String? _userName;

  /// Настройка блока/сети — только админ предприятия (не HydroMaker).
  bool get _canConfigureBlockNetwork => _isAdmin && !_isManufacturer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRole());
  }

  Future<void> _loadRole() async {
    final scope = CloudScope.of(context);
    final role = await scope.auth.currentRole();
    final name = await scope.auth.currentUserName();
    final admin = await scope.auth.isAdmin();
    var manufacturer = false;
    if (!await scope.tokens.isDemoSession()) {
      try {
        final me = await scope.organizations.fetchMe();
        manufacturer = me.isManufacturer;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _isManufacturer = manufacturer;
      _roleLabel = UserRoles.label(role);
      _userName = name;
    });
  }

  Future<void> _logout() async {
    await CloudScope.of(context).auth.logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : null,
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          return ListView(
            children: [
              if (_userName != null || _roleLabel != null)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(_userName ?? 'Пользователь'),
                  subtitle: Text(_roleLabel ?? ''),
                ),
              ListTile(
                title: const Text('Частота обновления'),
                subtitle: Text('${session.pollSeconds} сек'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Slider(
                  value: session.pollSeconds.toDouble(),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${session.pollSeconds} с',
                  onChanged: (v) => session.setPollSeconds(v.round()),
                ),
              ),
              const Divider(),
              if (_isAdmin) ...[
                ListTile(
                  title: const Text('Редактировать датчики'),
                  onTap: () => context.push('/sensors/setup?from=settings'),
                ),
                if (_canConfigureBlockNetwork)
                  ListTile(
                    leading: const Icon(Icons.settings_input_antenna),
                    title: const Text('Настройка блока и сети'),
                    subtitle: const Text(
                      'Wi‑Fi / GSM блока, адрес сервера API',
                    ),
                    onTap: () => context.push('/settings/network'),
                  ),
                ListTile(
                  title: const Text('Сменить режим работы'),
                  onTap: () => context.go('/mode'),
                ),
              ] else
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Настройки оборудования'),
                  subtitle: Text(
                    'Доступны только администратору (блок, датчики, сеть)',
                  ),
                ),
              ListTile(
                title: const Text('Выйти'),
                leading: const Icon(Icons.logout),
                onTap: _logout,
              ),
              const ListTile(
                title: Text('О приложении'),
                subtitle: Text('ГидроВин v1.1.0'),
              ),
            ],
          );
        },
      ),
    );
  }
}
