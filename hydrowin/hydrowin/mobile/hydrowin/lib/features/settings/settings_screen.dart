import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/app/theme_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/domain/user_roles.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAdmin = true;
  bool _isPlatform = false;
  bool _isManufacturer = false;
  bool _isClient = false;
  String? _accountLabel;
  String? _userName;

  /// Все админ-операции учёток и плат — по роли организации.
  bool get _isPlatformAdmin => _isAdmin && _isPlatform;

  bool get _demoFactory => DemoSession.isActive;

  bool get _canConfigureBlockNetwork => _isPlatformAdmin || _demoFactory;
  bool get _canCreateManufacturer => _isPlatformAdmin;
  bool get _canCreateFactory => _isAdmin && (_isPlatform || _isManufacturer);
  bool get _canCreateDriver =>
      _isAdmin && (_isPlatform || _isClient || _demoFactory);
  bool get _canManageUsers =>
      _isAdmin &&
      (_isPlatform || _isClient || _isManufacturer || _demoFactory);
  bool get _canManageOrgs => _isPlatformAdmin;
  bool get _canRegisterBoard => _isPlatformAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRole());
  }

  Future<void> _loadRole() async {
    if (AppConstants.isLite && !DemoSession.isActive) {
      if (mounted) {
        setState(() {
          _isAdmin = true;
          _accountLabel = 'Локальный режим';
          _userName = 'ГидроВин Lite';
        });
      }
      return;
    }
    if (DemoSession.isActive) {
      if (mounted) {
        setState(() {
          _isAdmin = true;
          _isPlatform = false;
          _isManufacturer = false;
          _isClient = true;
          _accountLabel = 'Демо завода';
          _userName = 'Админ завода (демо)';
        });
      }
      return;
    }
    final scope = CloudScope.of(context);
    final role = await scope.auth.currentRole();
    final name = await scope.auth.currentUserName();
    final admin = await scope.auth.isAdmin();
    var platform = false;
    var manufacturer = false;
    var client = false;
    var accountLabel = UserRoles.label(role);
    try {
      final me = await scope.organizations.fetchMe();
      platform = me.isPlatform;
      manufacturer = me.isManufacturer;
      client = me.isClient;
      if (me.isPlatform) {
        accountLabel = 'Админ платформы';
      } else if (me.isManufacturer) {
        accountLabel = 'Производитель';
      } else if (UserRoles.isDriver(role)) {
        accountLabel = 'Водитель';
      } else if (me.isClient) {
        accountLabel = 'Завод';
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _isPlatform = platform;
      _isManufacturer = manufacturer;
      _isClient = client;
      _accountLabel = accountLabel;
      _userName = name;
    });
  }

  Future<void> _logout() async {
    try {
      await AppScope.of(context).disconnect();
    } catch (_) {}
    try {
      await CloudScope.maybeOf(context)?.auth.logout();
    } catch (_) {}
    if (!mounted) return;
    if (AppConstants.isLite) {
      context.go('/lite');
      return;
    }
    context.go('/login');
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Светлая тема',
        ThemeMode.system => 'Как в системе',
        ThemeMode.dark => 'Тёмная тема',
      };

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final themeCtrl = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : null,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([session, themeCtrl]),
        builder: (context, _) {
          return ListView(
            children: [
              if (!AppConstants.isLite || DemoSession.isActive)
                if (_userName != null || _accountLabel != null)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(_userName ?? 'Пользователь'),
                    subtitle: Text(_accountLabel ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/settings/profile');
                      if (mounted) await _loadRole();
                    },
                  ),
              if (AppConstants.isLite && !DemoSession.isActive)
                const ListTile(
                  leading: Icon(Icons.bluetooth),
                  title: Text('ГидроВин Lite'),
                  subtitle: Text('Только Bluetooth · без учётной записи'),
                ),
              if (DemoSession.isActive)
                const ListTile(
                  leading: Icon(Icons.factory_outlined),
                  title: Text('Демо завода'),
                  subtitle: Text('Учебные данные · без реального сервера'),
                ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Оформление'),
                subtitle: Text(_themeLabel(themeCtrl.mode)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Тёмная'),
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Светлая'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('Система'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    ),
                  ],
                  selected: {themeCtrl.mode},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) themeCtrl.setMode(s.first);
                  },
                ),
              ),
              ListTile(
                title: const Text('Частота обновления'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Slider(
                  value: session.pollSeconds.toDouble(),
                  min: AppConstants.minPollSeconds.toDouble(),
                  max: AppConstants.maxPollSeconds.toDouble(),
                  divisions:
                      AppConstants.maxPollSeconds - AppConstants.minPollSeconds,
                  label: '${session.pollSeconds} с',
                  onChanged: (v) => session.setPollSeconds(v.round()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.history_edu_outlined),
                title: const Text('Журнал петли 4–20 мА'),
                subtitle: const Text(
                  'Обрыв / КЗ / критично · ток для гарантии',
                ),
                onTap: () => context.push('/settings/service-journal'),
              ),
              const Divider(),
              if (AppConstants.isLite && !DemoSession.isActive) ...[
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Главная Lite'),
                  subtitle: const Text('Bluetooth или демо завода'),
                  onTap: () => context.go('/lite'),
                ),
                if (AppConstants.demoAvailable)
                  ListTile(
                    leading: const Icon(Icons.factory_outlined),
                    title: const Text('Демо завода'),
                    subtitle: const Text(
                      'Парк, графики, уведомления — без сервера',
                    ),
                    onTap: () async {
                      await CloudScope.of(context).auth.loginDemo();
                      final prefs = await AppPreferences.create();
                      await prefs.setWorkMode(AppConstants.workModeFleet);
                      if (context.mounted) context.go('/fleet');
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.sensors_outlined),
                  title: const Text('Настройка датчиков'),
                  subtitle: const Text(
                    'Имя, шкала и пороги — только на этом устройстве',
                  ),
                  onTap: () => context.push('/sensors/setup?from=lite'),
                ),
                ListTile(
                  leading: const Icon(Icons.bluetooth_searching),
                  title: const Text('Подключить блок по Bluetooth'),
                  subtitle: const Text('Сканировать HydroWin…'),
                  onTap: () => context.go('/ble/connect'),
                ),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('Живые показания'),
                  subtitle: const Text('Экран датчиков после подключения'),
                  onTap: () => context.push('/machine'),
                ),
                const ListTile(
                  title: Text('О приложении'),
                  subtitle: Text(
                    'ГидроВин Lite · Bluetooth + демо завода',
                  ),
                ),
              ] else ...[
              if (_isAdmin)
                ListTile(
                  leading: const Icon(Icons.sensors_outlined),
                  title: const Text('Настройка датчиков'),
                  subtitle: const Text(
                    'Машина → имя, шкала и пороги (облако и BLE)',
                  ),
                  onTap: () => context.push('/sensors/thresholds'),
                ),
              ListTile(
                leading: const Icon(Icons.bluetooth_searching),
                title: const Text('Подключить блок по Bluetooth'),
                subtitle: const Text('Сканировать HydroWin… и связать блок'),
                onTap: () => context.push('/ble/connect'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Уведомления'),
                subtitle: const Text(
                  'Аварии → оповещения · скачки и входы → журнал',
                ),
                onTap: () => context.push('/notifications'),
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Каналы оповещений'),
                subtitle: const Text('Почта, Telegram'),
                onTap: () => context.push('/notifications/prefs'),
              ),
              if (_canCreateManufacturer ||
                  _canCreateFactory ||
                  _canCreateDriver ||
                  _canManageUsers ||
                  _canManageOrgs ||
                  _canRegisterBoard ||
                  _canConfigureBlockNetwork) ...[
                if (_canCreateManufacturer)
                  ListTile(
                    leading: const Icon(Icons.business),
                    title: const Text('Создать производителя'),
                    subtitle: const Text('Организация + админ'),
                    onTap: () => context.push('/admin/manufacturer'),
                  ),
                if (_canCreateFactory)
                  ListTile(
                    leading: const Icon(Icons.factory_outlined),
                    title: const Text('Создать завод'),
                    subtitle: Text(
                      _isPlatform
                          ? 'Под выбранным производителем'
                          : 'Завод под вашей организацией',
                    ),
                    onTap: () => context.push('/admin/factory'),
                  ),
                if (_canCreateDriver)
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_1_outlined),
                    title: const Text('Создать водителя'),
                    subtitle: const Text(
                      'Учётка завода с доступом к одной машине',
                    ),
                    onTap: () => context.push('/admin/driver'),
                  ),
                if (_canManageUsers)
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: Text(
                      _isClient
                          ? 'Пользователи завода'
                          : 'Заводы и водители',
                    ),
                    subtitle: Text(
                      _isClient
                          ? 'Список и удаление учёток'
                          : 'Заводы, водители и привязка к машинам',
                    ),
                    onTap: () => context.push('/admin/users'),
                  ),
                if (_canManageOrgs)
                  ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: const Text('Организации'),
                    subtitle: const Text(
                      'Производители и заводы — удаление с каскадом',
                    ),
                    onTap: () => context.push('/admin/orgs'),
                  ),
                if (_canRegisterBoard)
                  ListTile(
                    leading: const Icon(Icons.developer_board),
                    title: const Text('Зарегистрировать плату'),
                    subtitle: const Text(
                      'Машина + ключ платы — сразу в парке',
                    ),
                    onTap: () => context.push('/admin/register-board'),
                  ),
                if (_canConfigureBlockNetwork) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings_input_antenna),
                    title: const Text('Настройка блока и сети'),
                    subtitle: const Text(
                      'Wi‑Fi / GSM блока, адрес сервера API',
                    ),
                    onTap: () => context.push('/settings/network'),
                  ),
                ],
              ],
              ListTile(
                title: const Text('Выйти'),
                leading: const Icon(Icons.logout),
                onTap: _logout,
              ),
              const ListTile(
                title: Text('О приложении'),
                subtitle: Text('ГидроВин v1.2.0'),
              ),
              ],
            ],
          );
        },
      ),
    );
  }
}
