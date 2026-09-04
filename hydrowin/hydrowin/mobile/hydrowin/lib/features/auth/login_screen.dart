import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/api_config.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/domain/models/developer_settings.dart';
import 'package:hydrowin/widgets/brand_logo.dart';

/// Вход в облачный режим: админ платформы, производитель, завод.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;
  String _apiUrl = '';
  bool? _online;

  bool get _apiIsProduction {
    final current = _apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (current.isEmpty) return true;
    if (ApiConfig.shouldPreferProduction(current)) return false;
    final prod = ApiConfig.productionBaseUrl
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    return current == prod;
  }

  bool get _offline => _online == false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final scope = CloudScope.of(context);
    // Старые full-сборки с :8090 → сразу на HTTPS.
    if (ApiConfig.shouldPreferProduction(scope.api.baseUrl)) {
      await scope.developerSettings.save(const DeveloperSettings());
      scope.api.baseUrl = ApiConfig.productionBaseUrl;
    }
    final remembered = await scope.tokens.getRememberedCredentials();
    final remember = await scope.tokens.getRememberLogin();
    if (!mounted) return;
    setState(() {
      _apiUrl = scope.api.baseUrl;
      _remember = remember || remembered != null;
      if (remembered != null) {
        _email.text = remembered.email;
        // Пароль больше не восстанавливаем из хранилища.
      }
    });
    unawaited(_probeConnectivity());
  }

  Future<void> _probeConnectivity() async {
    final online = await _checkServerReachable(_apiUrl);
    if (!mounted) return;
    setState(() => _online = online);
  }

  /// Короткая проверка доступа к хосту API (без логина).
  Future<bool> _checkServerReachable(String apiBase) async {
    if (kIsWeb) return true;
    try {
      final raw = apiBase.trim();
      if (raw.isEmpty) return false;
      final base = Uri.parse(raw.endsWith('/') ? raw : '$raw/');
      final host = base.host;
      if (host.isEmpty) return false;
      final port = base.hasPort
          ? base.port
          : (base.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _resetApiToProduction() async {
    final scope = CloudScope.of(context);
    await scope.developerSettings.save(const DeveloperSettings());
    scope.api.baseUrl = ApiConfig.productionBaseUrl;
    if (!mounted) return;
    setState(() {
      _apiUrl = scope.api.baseUrl;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сервер сброшен на рабочий: $_apiUrl')),
    );
    unawaited(_probeConnectivity());
  }

  Future<void> _persistRememberChoice(String email, String password) async {
    final tokens = CloudScope.of(context).tokens;
    if (_remember) {
      await tokens.saveRememberedCredentials(email: email);
    } else {
      await tokens.clearRememberedCredentials();
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите email и пароль');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _apiUrl = CloudScope.of(context).api.baseUrl;
    });

    final auth = CloudScope.of(context).auth;
    try {
      await auth.login(email: email, password: password);
      await _persistRememberChoice(email, password);
      final prefs = await AppPreferences.create();
      await prefs.setWorkMode(AppConstants.workModeFleet);
      await prefs.setFirstLaunchDone();
      if (!mounted) return;
      context.go('/fleet');
    } catch (e) {
      if (!mounted) return;
      final offline = !(await _checkServerReachable(
        CloudScope.of(context).api.baseUrl,
      ));
      setState(() {
        _online = !offline;
        _error = offline
            ? '${auth.humanizeError(e)}\nНет связи с сервером — можно '
                'подключить блок по Bluetooth без интернета.'
            : '${auth.humanizeError(e)}\nAPI: ${CloudScope.of(context).api.baseUrl}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enterDemo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await CloudScope.of(context).auth.loginDemo();
      final prefs = await AppPreferences.create();
      await prefs.setWorkMode(AppConstants.workModeFleet);
      await prefs.setFirstLaunchDone();
      if (!mounted) return;
      context.go('/fleet');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось запустить демо: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enterBleOffline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await AppPreferences.create();
      await prefs.setWorkMode(AppConstants.workModeSingle);
      await prefs.setFirstLaunchDone();
      if (!mounted) return;
      context.go('/ble/connect');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(child: BrandLogo(size: 140)),
          if (_offline) ...[
            const SizedBox(height: 16),
            Card(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wifi_off, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Нет связи с сервером',
                            style: text.titleMedium?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Можно работать с блоком по Bluetooth без интернета '
                      'и без входа в аккаунт.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _enterBleOffline,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Подключить по Bluetooth'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
            ),
            enabled: !_loading,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Пароль',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            enabled: !_loading,
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Запомнить email'),
            subtitle: const Text('Пароль на устройстве не сохраняется'),
            value: _remember,
            onChanged: _loading
                ? null
                : (v) => setState(() => _remember = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (!_apiIsProduction) ...[
            const SizedBox(height: 4),
            Text(
              'Сейчас указан не основной сервер (например, после смены адреса '
              'в настройках блока). Можно вернуть рабочий HTTPS.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: _loading ? null : _resetApiToProduction,
              child: const Text('Вернуть основной сервер'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Войти'),
          ),
          if (!_offline) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _enterBleOffline,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Только Bluetooth (без интернета)'),
            ),
          ],
          if (AppConstants.demoAvailable) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _enterDemo,
              icon: const Icon(Icons.factory_outlined),
              label: const Text('Демо завода (без сервера)'),
            ),
            const SizedBox(height: 4),
            Text(
              'Парк, графики, уведомления и GSM — учебные данные',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
