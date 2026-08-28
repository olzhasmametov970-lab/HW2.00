import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';

/// Регистрация машины + платы: сразу появляется в парке.
class RegisterBoardScreen extends StatefulWidget {
  const RegisterBoardScreen({super.key});

  @override
  State<RegisterBoardScreen> createState() => _RegisterBoardScreenState();
}

class _RegisterBoardScreenState extends State<RegisterBoardScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _model = TextEditingController();
  final _deviceId = TextEditingController();
  List<ClientOrgSummary> _makers = const [];
  String? _makerId;
  bool _isPlatform = false;
  bool _loading = false;
  bool _allowed = false;
  String? _error;

  /// После успеха — ключ показывается один раз.
  String? _createdMachineId;
  String? _createdDeviceId;
  String? _createdDeviceKey;
  String? _serialCommands;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAndLoad());
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _model.dispose();
    _deviceId.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!admin || !me.isPlatform) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Доступно только администратору платформы'),
          ),
        );
        context.pop();
        return;
      }

      final makers = await scope.organizations.listManufacturers();
      if (!mounted) return;
      setState(() {
        _allowed = true;
        _isPlatform = true;
        _makers = makers;
        _makerId = makers.isNotEmpty ? makers.first.id : null;
      });
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    var deviceId = _deviceId.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _error = 'Укажите код и название машины');
      return;
    }
    if (_isPlatform && _makerId == null) {
      setState(
        () => _error =
            'Выберите производителя или сначала создайте его в настройках',
      );
      return;
    }
    if (deviceId.isEmpty) {
      deviceId = 'HW-$code';
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = CloudScope.of(context).auth;
    try {
      final created = await CloudScope.of(context).machines.createMachine(
        code: code,
        name: name,
        model: _model.text.trim(),
        deviceId: deviceId,
        manufacturerOrganizationId: _isPlatform ? _makerId : null,
      );
      if (!mounted) return;

      final device = created['device'] as Map<String, dynamic>?;
      final machineId = created['id'] as String? ?? '';
      final dId = device?['device_id'] as String? ?? deviceId;
      final key = device?['device_key'] as String? ?? '';

      final cmds = StringBuffer()
        ..writeln('DEVICE $dId')
        ..writeln('MACHINE $machineId');
      if (key.isNotEmpty) cmds.writeln('KEY $key');
      cmds
        ..writeln('API app.hydrowin.ru|443')
        ..writeln('CFG');

      setState(() {
        _createdMachineId = machineId;
        _createdDeviceId = dId;
        _createdDeviceKey = key.isEmpty ? null : key;
        _serialCommands = cmds.toString().trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _copyCommands() async {
    final text = _serialCommands;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Команды скопированы — вставьте в Serial')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_createdMachineId != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Плата зарегистрирована')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Машина уже в парке. Прошейте/отправьте команды на плату — '
              'после первой телеметрии статус станет онлайн.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('machine_id'),
              subtitle: SelectableText(_createdMachineId!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('device_id'),
              subtitle: SelectableText(_createdDeviceId ?? ''),
            ),
            if (_createdDeviceKey != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('device_key (один раз)'),
                subtitle: SelectableText(_createdDeviceKey!),
              ),
            const SizedBox(height: 12),
            if (_serialCommands != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _serialCommands!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _copyCommands,
              icon: const Icon(Icons.copy),
              label: const Text('Скопировать команды Serial'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.go('/fleet'),
              child: const Text('Открыть парк'),
            ),
            TextButton(
              onPressed: () =>
                  context.push('/cloud/machine/$_createdMachineId'),
              child: const Text('Открыть карточку машины'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Зарегистрировать плату')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Создаёт машину в облаке и ключ платы. После этого блок сразу '
            'виден в парке (офлайн до первой телеметрии).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (_isPlatform) ...[
            if (_makers.isEmpty)
              ListTile(
                leading: const Icon(Icons.warning_amber),
                title: const Text('Нет производителей'),
                subtitle: const Text('Создайте производителя в настройках'),
                trailing: TextButton(
                  onPressed: () => context.push('/admin/manufacturer'),
                  child: const Text('Создать'),
                ),
              )
            else
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _makerId,
                decoration: const InputDecoration(
                  labelText: 'Производитель (склад)',
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
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Код машины',
              hintText: '003',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Экскаватор цех 2',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Модель (необязательно)',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deviceId,
            decoration: const InputDecoration(
              labelText: 'device_id платы',
              hintText: 'HW-HYDRO-03',
              border: OutlineInputBorder(),
              helperText: 'Если пусто — HW-<код>',
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
                : const Text('Создать машину и ключ'),
          ),
        ],
      ),
    );
  }
}
