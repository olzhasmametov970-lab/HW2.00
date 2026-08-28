import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/app/notification_center.dart';
import 'package:hydrowin/data/remote/notifications_repository.dart';

/// Каналы аварийных оповещений: push / SMS / почта / Telegram.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  NotificationSettingsModel? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _applyLocalPushPref(NotificationSettingsModel s) {
    NotificationScope.of(context).setPushEnabled(s.critical.push);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await CloudScope.of(context).notifications.getSettings();
      if (!mounted) return;
      _applyLocalPushPref(s);
      setState(() {
        _settings = s;
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

  Future<void> _save({bool showSnack = true}) async {
    final s = _settings;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      final updated =
          await CloudScope.of(context).notifications.updateSettings(s);
      if (!mounted) return;
      _applyLocalPushPref(updated);
      setState(() {
        _settings = updated;
        _saving = false;
      });
      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки оповещений сохранены')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _testTelegram() async {
    final s = _settings;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      // Сначала сохраняем chat id, потом шлём тест.
      final updated =
          await CloudScope.of(context).notifications.updateSettings(s);
      await CloudScope.of(context).notifications.testTelegram();
      if (!mounted) return;
      _applyLocalPushPref(updated);
      setState(() {
        _settings = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тест отправлен в Telegram')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _testEmail() async {
    final s = _settings;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      final updated =
          await CloudScope.of(context).notifications.updateSettings(s);
      await CloudScope.of(context).notifications.testEmail();
      if (!mounted) return;
      _applyLocalPushPref(updated);
      setState(() {
        _settings = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тест отправлен на почту')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _patchCritical(ChannelPrefs Function(ChannelPrefs) fn) async {
    final s = _settings;
    if (s == null) return;
    final next = s.copyWith(critical: fn(s.critical));
    setState(() => _settings = next);
    _applyLocalPushPref(next);
    await _save(showSnack: false);
  }

  Future<void> _patchContacts(
    AlertContactsPrefs Function(AlertContactsPrefs) fn,
  ) async {
    final s = _settings;
    if (s == null) return;
    setState(() => _settings = s.copyWith(contacts: fn(s.contacts)));
  }

  Future<void> _patchQuietHours(bool enabled) async {
    final s = _settings;
    if (s == null) return;
    setState(() {
      _settings = s.copyWith(
        quietHours: s.quietHours.copyWith(enabled: enabled),
      );
    });
    await _save(showSnack: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы оповещений'),
        actions: [
          TextButton(
            onPressed: _saving || _settings == null
                ? null
                : () => _save(showSnack: true),
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
                      _settings?.policyDescription ??
                          'Оповещения только при реальных авариях. '
                              'Мелкие скачки пишутся в журнал без тревоги.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Аварии (critical)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Сразу сообщают инженеру: пуш, почта, Telegram.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Push в приложении'),
                      subtitle: const Text(
                        'Всплывающие уведомления и Windows toast',
                      ),
                      value: _settings!.critical.push,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              _patchCritical((c) => c.copyWith(push: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Звук'),
                      value: _settings!.critical.sound,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              _patchCritical((c) => c.copyWith(sound: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Электронная почта'),
                      value: _settings!.critical.email,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              _patchCritical((c) => c.copyWith(email: v)),
                    ),
                    if (_settings!.critical.email)
                      TextFormField(
                        initialValue: _settings!.contacts.email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'alerts@example.com',
                          helperText:
                              'Куда отправлять email-уведомления. '
                              'Письма с логотипом HydroWin.',
                        ),
                        onChanged: (v) => _patchContacts(
                          (c) => c.copyWith(email: v.trim()),
                        ),
                      ),
                    if (_settings!.critical.email) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _testEmail,
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('Проверить почту'),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Telegram'),
                      value: _settings!.critical.telegram,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              _patchCritical((c) => c.copyWith(telegram: v)),
                    ),
                    if (_settings!.critical.telegram)
                      TextFormField(
                        initialValue: _settings!.contacts.telegram,
                        decoration: const InputDecoration(
                          labelText: 'Telegram username',
                          hintText: '@ivanov',
                          helperText:
                              '1) Напишите боту HydroWin /start\n'
                              '2) Укажите здесь свой @username\n'
                              '3) Нажмите «Проверить Telegram»',
                        ),
                        onChanged: (v) => _patchContacts(
                          (c) => c.copyWith(telegram: v.trim()),
                        ),
                      ),
                    if (_settings!.critical.telegram) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _testTelegram,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Проверить Telegram'),
                      ),
                    ],
                    const Divider(height: 32),
                    Text(
                      'Тихие часы',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Не беспокоить ночью'),
                      subtitle: Text(
                        '${_settings!.quietHours.from} – ${_settings!.quietHours.to}',
                      ),
                      value: _settings!.quietHours.enabled,
                      onChanged: _saving
                          ? null
                          : (v) => _patchQuietHours(v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Предупреждения (warning) всегда только в журнале — '
                      'каналы оповещения для них отключены.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
    );
  }
}
