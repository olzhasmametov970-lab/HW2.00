import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/api_config.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/developer_settings.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/network_settings.dart';

/// Настройка блока: станция → ключ платы → Wi‑Fi/GSM/API → USB-команды в Serial.
class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  static const _defaultHost = 'app.hydrowin.ru';
  static const _defaultPort = 443;

  final _wifiSsid = TextEditingController();
  final _wifiPass = TextEditingController();
  final _gsmApn = TextEditingController();
  final _gsmUser = TextEditingController();
  final _gsmPass = TextEditingController();
  final _apiHost = TextEditingController();
  final _apiPort = TextEditingController();
  final _deviceId = TextEditingController();
  final _deviceKey = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _loadingDevices = false;
  bool _creatingDevice = false;
  bool _useCustomApi = false;
  String _linkMode = AppConstants.BLOCKLinkAuto;

  List<MachineSummary> _machines = const [];
  List<_DeviceRow> _devices = const [];
  String? _selectedMachineId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAndLoad());
  }

  /// Только админ платформы; производитель и завод — назад в настройки.
  Future<void> _guardAndLoad() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!me.isPlatform || !admin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Настройка блока и сети доступна только администратору платформы',
            ),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    await _load();
  }

  @override
  void dispose() {
    _wifiSsid.dispose();
    _wifiPass.dispose();
    _gsmApn.dispose();
    _gsmUser.dispose();
    _gsmPass.dispose();
    _apiHost.dispose();
    _apiPort.dispose();
    _deviceId.dispose();
    _deviceKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final scope = CloudScope.of(context);
    try {
      final settings = await scope.networkSettings.load();
      final dev = scope.developerSettings.load();
      final fleet = await scope.machines.listMachines();
      if (!mounted) return;

      final machines = fleet.items;
      final ids = machines.map((m) => m.id).toSet();
      var machineId = settings.selectedMachineId.trim();
      if (machineId.isEmpty || !ids.contains(machineId)) {
        machineId = machines.isNotEmpty ? machines.first.id : '';
      }

      _applyNetwork(settings);
      _applyApi(dev);
      setState(() {
        _machines = machines;
        _selectedMachineId = machineId.isEmpty ? null : machineId;
        _deviceId.text = settings.selectedDeviceId;
        _deviceKey.text = settings.deviceKey;
        _loading = false;
      });

      if (machineId.isNotEmpty) {
        await _loadDevices(
          machineId,
          preferDeviceId: settings.selectedDeviceId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось загрузить: $e')));
    }
  }

  void _applyNetwork(NetworkSettings s) {
    _wifiSsid.text = s.wifiSsid;
    _wifiPass.text = s.wifiPassword;
    _gsmApn.text = s.gsmApn;
    _gsmUser.text = s.gsmApnUser;
    _gsmPass.text = s.gsmApnPass;
    if (s.isGsm) {
      _linkMode = AppConstants.BLOCKLinkGsm;
    } else if (s.isAuto) {
      _linkMode = AppConstants.BLOCKLinkAuto;
    } else {
      _linkMode = AppConstants.BLOCKLinkWifi;
    }
  }

  void _applyApi(DeveloperSettings dev) {
    _useCustomApi = dev.useCustomServer && dev.serverHost.trim().isNotEmpty;
    _apiHost.text = _useCustomApi ? dev.serverHost : _defaultHost;
    _apiPort.text = '${_useCustomApi ? dev.apiPort : _defaultPort}';
  }

  Future<void> _loadDevices(String machineId, {String? preferDeviceId}) async {
    setState(() => _loadingDevices = true);
    try {
      final raw = await CloudScope.of(
        context,
      ).machines.listMachineDevices(machineId);
      if (!mounted) return;
      final devices = raw
          .map(
            (m) => _DeviceRow(
              id: m['id'] as String? ?? '',
              deviceId: m['device_id'] as String? ?? '',
            ),
          )
          .where((d) => d.deviceId.isNotEmpty)
          .toList();

      var prefer = (preferDeviceId ?? _deviceId.text).trim();
      if (prefer.isEmpty || !devices.any((d) => d.deviceId == prefer)) {
        prefer = devices.isNotEmpty ? devices.first.deviceId : prefer;
      }

      setState(() {
        _devices = devices;
        if (prefer.isNotEmpty) _deviceId.text = prefer;
        _loadingDevices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _loadingDevices = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Список плат не загрузился ($e). '
            'Можно ввести device_id и ключ вручную.',
          ),
        ),
      );
    }
  }

  NetworkSettings _buildNetwork() {
    return NetworkSettings(
      BLOCKLinkType: _linkMode,
      wifiSsid: _wifiSsid.text.trim(),
      wifiPassword: _wifiPass.text,
      gsmApn: _gsmApn.text.trim(),
      gsmApnUser: _gsmUser.text.trim(),
      gsmApnPass: _gsmPass.text,
      selectedMachineId: _selectedMachineId ?? '',
      selectedDeviceId: _deviceId.text.trim(),
      deviceKey: _deviceKey.text.trim(),
    );
  }

  (String host, int port) _apiHostPort() {
    if (!_useCustomApi) return (_defaultHost, _defaultPort);
    final host = _apiHost.text.trim().isEmpty
        ? _defaultHost
        : _apiHost.text.trim();
    final port = int.tryParse(_apiPort.text.trim()) ?? _defaultPort;
    return (host, port);
  }

  MachineSummary? get _selectedMachine {
    final id = _selectedMachineId;
    if (id == null) return null;
    for (final m in _machines) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _onMachineChanged(String? machineId) async {
    if (machineId == null) return;
    setState(() {
      _selectedMachineId = machineId;
      _devices = const [];
      _deviceId.clear();
      _deviceKey.clear();
    });
    await _loadDevices(machineId);
  }

  Future<void> _createDevice() async {
    final machine = _selectedMachine;
    if (machine == null) return;

    final labelCtrl = TextEditingController(
      text: 'HW-HYDRO-${(_devices.length + 1).toString().padLeft(2, '0')}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый ключ платы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Для «${machine.name}». Ключ покажется один раз — '
              'сразу скопируйте команды в Serial этой платы.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'device_id (метка платы)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      labelCtrl.dispose();
      return;
    }

    setState(() => _creatingDevice = true);
    try {
      final created = await CloudScope.of(context).machines.createMachineDevice(
        machine.id,
        deviceId: labelCtrl.text.trim(),
      );
      if (!mounted) return;
      final deviceId = created['device_id'] as String? ?? '';
      final key = created['device_key'] as String? ?? '';
      setState(() {
        if (deviceId.isNotEmpty) {
          _devices = [
            ..._devices.where((d) => d.deviceId != deviceId),
            _DeviceRow(id: created['id'] as String? ?? '', deviceId: deviceId),
          ];
          _deviceId.text = deviceId;
        }
        if (key.isNotEmpty) _deviceKey.text = key;
        _creatingDevice = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ключ создан. Нажмите «Скопировать команды» и вставьте в Serial.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creatingDevice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    } finally {
      labelCtrl.dispose();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final scope = CloudScope.of(context);
      final net = _buildNetwork();
      await scope.networkSettings.save(net);

      final (host, port) = _apiHostPort();
      final path = scope.developerSettings.load().apiPath;
      await scope.developerSettings.save(
        DeveloperSettings(
          serverHost: host,
          apiPort: port,
          apiPath: path.isEmpty ? '/v1' : path,
          useCustomServer: _useCustomApi,
          BLOCKPort: scope.developerSettings.load().BLOCKPort,
        ),
      );
      scope.api.baseUrl = scope.serverConfig.resolveApiBaseUrl();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Сохранено в приложении')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyUsbCommands() async {
    final net = _buildNetwork();
    if (net.selectedMachineId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите станцию (машину)')),
      );
      return;
    }
    if (net.selectedDeviceId.isEmpty || net.deviceKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Нужны device_id и ключ: создайте новый ключ или вставьте сохранённый.',
          ),
        ),
      );
      return;
    }
    if ((net.isWifi || net.isAuto) && net.wifiSsid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Укажите SSID Wi‑Fi')));
      return;
    }
    if ((net.isGsm || net.isAuto) && net.gsmApn.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Укажите APN для GSM')));
      return;
    }

    await _save();
    if (!mounted) return;

    final (host, port) = _apiHostPort();
    final text = net.toBlockUsbCommands(apiHost: host, apiPort: port);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    final machine = _selectedMachine;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Команды для «${machine?.name ?? 'машины'}» скопированы. '
          'Вставьте в Serial Monitor платы (115200):\n$text',
        ),
        duration: const Duration(seconds: 14),
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Прошивка: ${machine?.name ?? 'машина'}'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Подключите нужную плату по USB и вставьте:\n\n$text\n\n'
            'MACHINE / DEVICE / KEY — привязка к выбранной станции.\n'
            'CFG сохраняет всё в NVS платы.\n\n'
            'Если в мониторе ещё старый Wi‑Fi (например R2D2) — '
            'команды после смены SSID ещё не вставляли.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetNetworkDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить сеть?'),
        content: const Text(
          'Wi‑Fi / GSM / режим связи — к значениям по умолчанию. '
          'Выбранная машина и ключ не трогаются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cur = _buildNetwork();
    _applyNetwork(
      NetworkSettings(
        selectedMachineId: cur.selectedMachineId,
        selectedDeviceId: cur.selectedDeviceId,
        deviceKey: cur.deviceKey,
      ),
    );
    setState(() {
      _useCustomApi = false;
      _apiHost.text = _defaultHost;
      _apiPort.text = '$_defaultPort';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка блока и сети'),
        actions: [
          IconButton(
            tooltip: 'Сбросить сеть',
            onPressed: _loading || _saving ? null : _resetNetworkDefaults,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  'Одна плата = одна станция. Выберите машину, создайте или '
                  'вставьте ключ, затем скопируйте команды в Serial этой платы.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Станция (MACHINE_ID)',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_machines.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Нет машин в аккаунте. Создайте станцию на экране парка.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _selectedMachineId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Машина',
                    ),
                    items: [
                      for (final m in _machines)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.name} (${m.code})'),
                        ),
                    ],
                    onChanged: _saving ? null : _onMachineChanged,
                  ),
                if (_selectedMachine != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'MACHINE_ID: ${_selectedMachine!.id}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Плата / ключ (X-Device-Key)',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _saving ||
                              _creatingDevice ||
                              _selectedMachineId == null
                          ? null
                          : _createDevice,
                      icon: _creatingDevice
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Новый ключ'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingDevices)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_devices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _devices.any((d) => d.deviceId == _deviceId.text)
                        ? _deviceId.text
                        : null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Устройство из списка',
                    ),
                    items: [
                      for (final d in _devices)
                        DropdownMenuItem(
                          value: d.deviceId,
                          child: Text(d.deviceId),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (id) {
                            if (id == null) return;
                            setState(() => _deviceId.text = id);
                          },
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deviceId,
                  decoration: const InputDecoration(
                    labelText: 'device_id (DEVICE …)',
                    border: OutlineInputBorder(),
                    helperText: 'Можно ввести вручную',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deviceKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'device_key (KEY …)',
                    border: OutlineInputBorder(),
                    helperText:
                        'API не отдаёт старый ключ повторно — только при создании',
                  ),
                ),
                const SizedBox(height: 20),
                Text('Режим связи', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: AppConstants.BLOCKLinkWifi,
                      label: Text('Wi‑Fi'),
                      icon: Icon(Icons.wifi),
                    ),
                    ButtonSegment(
                      value: AppConstants.BLOCKLinkAuto,
                      label: Text('Auto'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                    ButtonSegment(
                      value: AppConstants.BLOCKLinkGsm,
                      label: Text('GSM'),
                      icon: Icon(Icons.cell_tower),
                    ),
                  ],
                  selected: {_linkMode},
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    setState(() => _linkMode = s.first);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _linkMode == AppConstants.BLOCKLinkAuto
                      ? 'Нет Wi‑Fi → GSM; нет GSM → Wi‑Fi. Нужны и SSID, и APN.'
                      : _linkMode == AppConstants.BLOCKLinkWifi
                      ? 'Только Wi‑Fi объекта.'
                      : 'Только SIM900A + SIM.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text('Wi‑Fi на объекте', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _wifiSsid,
                  decoration: const InputDecoration(
                    labelText: 'SSID сети',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _wifiPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль Wi‑Fi',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('GSM / APN (SIM)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _gsmApn,
                  decoration: const InputDecoration(
                    labelText: 'APN',
                    hintText: 'internet.mts.ru',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gsmUser,
                  decoration: const InputDecoration(
                    labelText: 'Пользователь APN',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gsmPass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль APN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Сервер API', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'По умолчанию: ${ApiConfig.defaultBaseUrl}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Другой сервер'),
                  subtitle: const Text('Только если меняете IP / порт'),
                  value: _useCustomApi,
                  onChanged: (v) {
                    setState(() {
                      _useCustomApi = v;
                      if (!v) {
                        _apiHost.text = _defaultHost;
                        _apiPort.text = '$_defaultPort';
                      }
                    });
                  },
                ),
                TextField(
                  controller: _apiHost,
                  enabled: _useCustomApi,
                  decoration: const InputDecoration(
                    labelText: 'Хост / IP',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiPort,
                  enabled: _useCustomApi,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Порт',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _copyUsbCommands,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Скопировать команды для этой платы'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'Сохранение…' : 'Сохранить в приложении',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'В мониторе порта видно NVS платы. Пока не вставите новые '
                  'команды + CFG, там останется старый Wi‑Fi (например R2D2).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeviceRow {
  const _DeviceRow({required this.id, required this.deviceId});

  final String id;
  final String deviceId;
}
