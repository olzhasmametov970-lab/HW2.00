import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/developer_settings.dart';
import 'package:go_router/go_router.dart';

class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  final _password = TextEditingController();
  bool _unlocked = false;
  bool _checking = true;

  late DeveloperSettings _settings;
  late TextEditingController _host;
  late TextEditingController _apiPort;
  late TextEditingController _BLOCKPort;
  late TextEditingController _apiPath;
  bool _useCustom = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final devRepo = CloudScope.of(context).developerSettings;
    _unlocked = devRepo.isUnlocked;
    _settings = devRepo.load();
    _host = TextEditingController(text: _settings.serverHost);
    _apiPort = TextEditingController(text: '${_settings.apiPort}');
    _BLOCKPort = TextEditingController(text: '${_settings.BLOCKPort}');
    _apiPath = TextEditingController(text: _settings.apiPath);
    _useCustom = _settings.useCustomServer;
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _password.dispose();
    _host.dispose();
    _apiPort.dispose();
    _BLOCKPort.dispose();
    _apiPath.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final ok = await CloudScope.of(
      context,
    ).developerSettings.verifyPassword(_password.text);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
      return;
    }
    await CloudScope.of(context).developerSettings.setUnlocked(true);
    if (mounted) setState(() => _unlocked = true);
  }

  Future<void> _save() async {
    final scope = CloudScope.of(context);
    final apiPort = int.tryParse(_apiPort.text.trim()) ?? 8090;
    final BLOCKPort = int.tryParse(_BLOCKPort.text.trim()) ?? 80;

    final updated = DeveloperSettings(
      serverHost: _host.text.trim(),
      apiPort: apiPort,
      BLOCKPort: BLOCKPort,
      apiPath: _apiPath.text.trim().isEmpty ? '/v1' : _apiPath.text.trim(),
      useCustomServer: _useCustom,
    );

    await scope.developerSettings.save(updated);
    scope.api.baseUrl = scope.serverConfig.resolveApiBaseUrl();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранено. API: ${scope.api.baseUrl}')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Режим разработчика')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Доступ к настройке IP, портов и адреса API защищён паролем.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль разработчика',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _unlock, child: const Text('ВОЙТИ')),
              const SizedBox(height: 8),
              Text(
                'Пароль по умолчанию: ${AppConstants.defaultDeveloperPassword}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим разработчика'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Свой сервер API'),
            subtitle: const Text('Иначе используется адрес из сборки'),
            value: _useCustom,
            onChanged: (v) => setState(() => _useCustom = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _host,
            enabled: _useCustom,
            decoration: const InputDecoration(
              labelText: 'IP или хост сервера',
              hintText: '5.165.27.141',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiPort,
            enabled: _useCustom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Порт API',
              hintText: '8090',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiPath,
            enabled: _useCustom,
            decoration: const InputDecoration(
              labelText: 'Путь API',
              hintText: '/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _BLOCKPort,
            decoration: const InputDecoration(
              labelText: 'Порт блока (справочно)',
              hintText: '80',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('СОХРАНИТЬ')),
        ],
      ),
    );
  }
}
