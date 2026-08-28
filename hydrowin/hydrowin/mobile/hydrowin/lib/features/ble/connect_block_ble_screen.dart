import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/data/ble/ble_block_client.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

/// Скан HydroWin-* → connect → Wi‑Fi/API команды + живые датчики.
class ConnectBlockBleScreen extends StatefulWidget {
  const ConnectBlockBleScreen({super.key});

  @override
  State<ConnectBlockBleScreen> createState() => _ConnectBlockBleScreenState();
}

class _ConnectBlockBleScreenState extends State<ConnectBlockBleScreen> {
  final _client = BleBlockClient();
  final _wifiSsid = TextEditingController();
  final _wifiPass = TextEditingController();
  final _apiHost = TextEditingController(text: 'app.hydrowin.ru');
  final _apiPort = TextEditingController(text: '443');

  List<BleDiscoveredBlock> _devices = const [];
  List<MachineSummary> _fleet = const [];
  String? _connectedName;
  String? _connectedId;
  String? _boundMachineId;
  String? _status;
  String? _lastReply;
  bool _scanning = false;
  bool _busy = false;

  /// Wi‑Fi / API на плату — только админ платформы.
  bool _canSendWifiApi = false;

  StreamSubscription? _devSub;
  StreamSubscription? _textSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _devSub?.cancel();
    _textSub?.cancel();
    _client.dispose();
    _wifiSsid.dispose();
    _wifiPass.dispose();
    _apiHost.dispose();
    _apiPort.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!_client.isSupported) {
      setState(
        () => _status =
            'BLE недоступен на этой платформе (нужны Android / iOS / Windows)',
      );
      return;
    }
    // Lite и офлайн full: только Bluetooth, без запросов к серверу.
    if (!AppConstants.isLite) {
      try {
        final scope = CloudScope.maybeOf(context);
        if (scope != null && await scope.auth.isLoggedIn()) {
          final admin = await scope.auth.isAdmin();
          var canWifi = false;
          if (admin) {
            try {
              final me = await scope.organizations.fetchMe();
              canWifi = me.isPlatform;
            } catch (_) {
              canWifi = false;
            }
          }
          try {
            final fleet = await scope.machines.listMachines();
            if (mounted) {
              setState(() {
                _canSendWifiApi = canWifi;
                _fleet = fleet.items;
              });
            }
          } catch (_) {
            if (mounted) setState(() => _canSendWifiApi = canWifi);
          }
        }
      } catch (_) {
        // роль не критична для скана
      }
    }

    _devSub = _client.devices.listen((list) {
      if (mounted) setState(() => _devices = list);
    });
    _textSub = _client.textMessages.listen((msg) {
      if (mounted) setState(() => _lastReply = msg);
    });
  }

  MachineSummary? _findFleetMachine(String bleName) {
    var idPart = bleName;
    if (idPart.startsWith('HydroWin-')) {
      idPart = idPart.substring('HydroWin-'.length);
    } else if (idPart.startsWith('HydroWin')) {
      idPart = idPart.substring('HydroWin'.length);
    }
    idPart = idPart.trim();
    if (idPart.isEmpty) return null;
    final needle = idPart.toLowerCase();
    final bleLower = bleName.trim().toLowerCase();

    bool codesEqual(String code) {
      final a = code.trim().toLowerCase();
      if (a == needle) return true;
      final na = int.tryParse(a);
      final nb = int.tryParse(needle);
      // «2» == «002», но не «21»
      if (na != null && nb != null) return na == nb;
      return false;
    }

    MachineSummary? exact;
    for (final m in _fleet) {
      if (m.id.toLowerCase() == needle) return m;
      if (m.name.trim().toLowerCase() == bleLower) return m;
      if (m.name.trim().toLowerCase() == needle) return m;
      if (codesEqual(m.code)) {
        exact ??= m;
      }
    }
    return exact;
  }

  bool _matchesFleet(String bleName) => _findFleetMachine(bleName) != null;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = 'Поиск HydroWin…';
      _devices = const [];
    });
    try {
      await _client.startScan();
      if (mounted) setState(() => _status = 'Скан завершён');
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BleDiscoveredBlock d) async {
    final session = AppScope.of(context);
    final weak = d.rssi < -75;
    setState(() {
      _busy = true;
      _status = weak
          ? 'Подключение к ${d.name}… (слабый сигнал ${d.rssi}, поднесите ближе)'
          : 'Подключение к ${d.name}…';
    });
    try {
      await _client.connect(d.id, rssi: d.rssi);
      final machine = _findFleetMachine(d.name);
      await session.startBle(
        label: d.name,
        packetStream: _client.packets,
        machineId: machine?.id,
        deviceId: d.id,
      );
      if (!mounted) return;
      final label = session.deviceLabel ?? d.name;
      setState(() {
        _connectedName = label;
        _connectedId = d.id;
        _boundMachineId = machine?.id;
        _status = AppConstants.isLite
            ? 'Подключено: $label · данные только по Bluetooth'
            : machine == null
            ? 'Подключено: $label · машина в парке не найдена — '
                  'пороги задайте в «Настройка датчиков»'
            : 'Подключено: $label · пороги с машины ${machine.code}';
      });
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Bad state: ', '');
        setState(() => _status = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWifi() async {
    if (!_canSendWifiApi) {
      setState(() => _status = 'Wi‑Fi/API доступны только админу платформы');
      return;
    }
    final ssid = _wifiSsid.text.trim();
    if (ssid.isEmpty) {
      setState(() => _status = 'Укажите SSID');
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.writeLine('WIFI $ssid|${_wifiPass.text}');
      await _client.writeLine(
        'API ${_apiHost.text.trim()}|${_apiPort.text.trim()}',
      );
      await _client.writeLine('LINK wifi');
      await _client.writeLine('CFG');
      setState(() => _status = 'Команды отправлены');
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await AppScope.of(context).disconnect();
    await _client.disconnect();
    if (mounted) {
      setState(() {
        _connectedName = null;
        _connectedId = null;
        _boundMachineId = null;
        _status = 'Отключено';
      });
    }
  }

  Future<void> _renameConnectedBlock() async {
    final id = _connectedId;
    if (id == null) return;
    final session = AppScope.of(context);
    final controller = TextEditingController(text: _connectedName ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Имя блока'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Например: Кран 1, Стрела',
              helperText: 'Только на этом компьютере / телефоне',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || !mounted) return;
    await session.setBleDisplayName(next);
    if (!mounted) return;
    final label = session.deviceLabel ?? next.trim();
    setState(() {
      _connectedName = label.isEmpty ? id : label;
      _status = AppConstants.isLite
          ? 'Подключено: $_connectedName · данные только по Bluetooth'
          : _status;
    });
  }

  Color _statusColor(SensorStatusLevel status) {
    return AppTheme.statusColor(status, context);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConstants.isLite
              ? 'ГидроВин Lite · Bluetooth'
              : 'Подключить блок по Bluetooth',
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          if (_connectedName != null)
            IconButton(
              tooltip: 'Отключить',
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final enabledChannels = {
            for (final c in session.configs)
              if (c.enabled) c.channelIndex,
          };
          final readings = session.readings.values
              .where((r) => enabledChannels.contains(r.config.channelIndex))
              .toList()
            ..sort(
              (a, b) => a.config.channelIndex.compareTo(b.config.channelIndex),
            );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_client.isSupported)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Bluetooth в этой сборке недоступен. '
                      'Нужны Android, iOS или Windows с включённым Bluetooth.',
                    ),
                  ),
                )
              else ...[
                Text(
                  AppConstants.isLite
                      ? 'Работает без интернета. Скан → связать блок → '
                            'живые датчики на этом устройстве. Учётная запись '
                            'и сервер не нужны.'
                      : _canSendWifiApi
                      ? 'Скан → связать блок → при необходимости Wi‑Fi/API, '
                            'ниже — живые датчики. '
                            'На Windows ищите устройство в этом окне, не в '
                            '«Параметры → Bluetooth».'
                      : 'Офлайн-режим: скан → связать блок → живые датчики. '
                            'Интернет не обязателен. Wi‑Fi на плату задаёт '
                            'только администратор платформы (после входа).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (_scanning || _busy) ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(_scanning ? 'Сканирование…' : 'Найти блоки'),
                ),
                if (AppConstants.isLite) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/lite'),
                    child: const Text('На главную Lite'),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('К входу (облако)'),
                  ),
                ],
                if (AppConstants.isLite && AppConstants.demoAvailable) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await CloudScope.of(context).auth.loginDemo();
                      final prefs = await AppPreferences.create();
                      await prefs.setWorkMode(AppConstants.workModeFleet);
                      if (context.mounted) context.go('/fleet');
                    },
                    icon: const Icon(Icons.factory_outlined),
                    label: const Text('Демо завода'),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (_lastReply != null && _canSendWifiApi) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Плата: $_lastReply',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                const SizedBox(height: 12),
                if (_connectedName == null)
                  ..._devices.map((d) {
                    final known = _matchesFleet(d.name);
                    final title = session.resolveBleLabel(d.id, d.name);
                    final macTail = BleBlockClient.shortMacTail(d.id);
                    return ListTile(
                      leading: Icon(
                        Icons.developer_board,
                        color: known
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(title),
                      subtitle: Text(
                        known
                            ? 'Есть в вашем парке · RSSI ${d.rssi}'
                            : d.rssi < -75
                            ? 'MAC …$macTail · слабый сигнал ${d.rssi}'
                            : 'MAC …$macTail · RSSI ${d.rssi}',
                      ),
                      trailing: FilledButton(
                        onPressed: _busy ? null : () => _connect(d),
                        child: const Text('Связать'),
                      ),
                    );
                  })
                else ...[
                  ListTile(
                    leading: const Icon(Icons.bluetooth_connected),
                    title: Text(_connectedName!),
                    subtitle: Text(
                      _canSendWifiApi
                          ? 'BLE активен'
                          : 'BLE активен · только просмотр данных',
                    ),
                    trailing: AppConstants.isLite
                        ? TextButton(
                            onPressed: _busy ? null : _renameConnectedBlock,
                            child: const Text('Имя'),
                          )
                        : null,
                  ),
                  if (_canSendWifiApi) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Wi‑Fi / API',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Только администратор платформы',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _wifiSsid,
                      decoration: const InputDecoration(
                        labelText: 'Wi‑Fi SSID',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _wifiPass,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Wi‑Fi пароль',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiHost,
                      decoration: const InputDecoration(labelText: 'API host'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiPort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'API port'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _sendWifi,
                      child: const Text('Отправить на плату'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _client.writeLine('CFG');
                            },
                      child: const Text('Запросить CFG'),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Живые каналы',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          if (AppConstants.isLite) {
                            context.push('/sensors/setup?from=ble');
                            return;
                          }
                          final id =
                              _boundMachineId ??
                              AppScope.of(context).boundMachineId;
                          if (id != null && id.isNotEmpty) {
                            context.push('/sensors/thresholds/$id');
                          } else {
                            context.push('/sensors/thresholds');
                          }
                        },
                        icon: const Icon(Icons.sensors_outlined, size: 18),
                        label: const Text('Настройка датчиков'),
                      ),
                    ],
                  ),
                  Text(
                    AppConstants.isLite
                        ? 'Имя, шкала и пороги — на телефоне, отдельно для каждого '
                              'блока. Подключите нужную плату, затем «Настройка датчиков».'
                        : 'Имя, шкала и пороги — только через «Настройка датчиков» '
                              '(облако). При связи с машиной из парка они подтягиваются '
                              'автоматически для BLE.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (readings.isEmpty)
                    const Text('Ждём пакет телеметрии…')
                  else
                    ...readings.map((r) {
                      final accent = _statusColor(r.status);
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.sensors, color: accent),
                          title: Text(r.config.name),
                          subtitle: Text(
                            'CH${r.config.channelIndex} · ${r.status.name} · '
                            '${r.formattedServiceCurrent}',
                          ),
                          trailing: Text(
                            r.formattedValue,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(color: accent),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.push('/machine'),
                    child: const Text('Открыть экран датчиков'),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
