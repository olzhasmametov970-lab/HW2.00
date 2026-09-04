import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/core/media/media_url.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart' show TelemetrySession;
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/sensor_display_format.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';
import 'package:hydrowin/features/fleet/cloud_sensor_chart_popup.dart';
import 'package:hydrowin/features/fleet/widgets/circular_sensor_gauge.dart';
import 'package:hydrowin/features/fleet/widgets/machine_location_map_card.dart';
import 'package:hydrowin/features/fleet/widgets/machine_status_chip.dart';
import 'package:hydrowin/core/format/duration_format.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/domain/loop_current.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Детали машины в облаке: датчики, сведения, GPS-карта.
class CloudMachineDetailScreen extends StatefulWidget {
  const CloudMachineDetailScreen({required this.machineId, super.key});

  final String machineId;

  @override
  State<CloudMachineDetailScreen> createState() =>
      _CloudMachineDetailScreenState();
}

class _CloudMachineDetailScreenState extends State<CloudMachineDetailScreen> {
  MachineSummary? _machine;
  List<CloudSensor> _sensors = [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _isAdmin = false;
  bool _isManufacturer = false;
  bool _isPlatform = false;

  /// Админ платформы (не админ завода client).
  bool get _isPlatformAdmin => _isAdmin && _isPlatform;

  List<ClientOrgSummary> _clients = [];
  List<ClientOrgSummary> _manufacturers = [];

  /// Последние значения с сервера (sensorId → value).
  final Map<String, double> _liveValues = {};
  final Map<String, SensorStatusLevel> _liveStatus = {};
  final Map<String, LoopFault> _liveFaults = {};
  final Map<String, double?> _liveCurrentMa = {};
  /// Время последней точки на сервере (не время опроса приложения).
  DateTime? _lastServerPointAt;
  List<MachineTrackPoint> _track = [];
  Timer? _liveTimer;
  int _liveRefreshGen = 0;
  DateTime? _liveUpdatedAt;
  TelemetrySession? _telemetry;
  int? _boundPollSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final scope = CloudScope.of(context);
      final admin = await scope.auth.isAdmin();
      if (mounted) setState(() => _isAdmin = admin);

      // Сначала карточка машины — не ждём списки орг (они могут тормозить).
      await _load();
      if (!mounted) return;
      _telemetry = AppScope.of(context);
      _telemetry!.addListener(_onPollIntervalChanged);
      _restartLiveTimer();
      unawaited(_loadOrgSideData(admin));
    });
  }

  void _onPollIntervalChanged() {
    final seconds = _telemetry?.pollSeconds;
    if (seconds == null || seconds == _boundPollSeconds) return;
    _restartLiveTimer();
  }

  void _restartLiveTimer() {
    _liveTimer?.cancel();
    final seconds =
        (_telemetry?.pollSeconds ?? AppConstants.defaultPollSeconds)
            .clamp(AppConstants.minPollSeconds, AppConstants.maxPollSeconds);
    _boundPollSeconds = seconds;
    // Сразу опросить, не ждать первый тик таймера.
    unawaited(_refreshLiveValues());
    _liveTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => unawaited(_refreshLiveValues()),
    );
  }

  Future<void> _loadOrgSideData(bool admin) async {
    try {
      final scope = CloudScope.of(context);
      final me = await scope.organizations.fetchMe();
      if (!mounted) return;

      // Тип org всегда из /me: завод/производитель ≠ платформа.
      setState(() {
        _isPlatform = me.isPlatform;
        _isManufacturer = me.isManufacturer;
      });

      // Служебные списки — только админ платформы / производителя.
      if (me.isPlatform && admin) {
        final makers = await scope.organizations.listManufacturers();
        if (mounted) setState(() => _manufacturers = makers);
      } else if (me.isManufacturer && admin) {
        final clients = await scope.organizations.listClients();
        if (mounted) setState(() => _clients = clients);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _telemetry?.removeListener(_onPollIntervalChanged);
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _machine == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final repo = CloudScope.of(context).machines;
    final auth = CloudScope.of(context).auth;

    try {
      final results = await Future.wait([
        repo.getMachine(widget.machineId),
        repo.listSensors(widget.machineId),
        repo.getTrack(
          widget.machineId,
          from: DateTime.now().subtract(const Duration(hours: 24)),
          limit: 500,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _machine = results[0] as MachineSummary?;
        _sensors = results[1] as List<CloudSensor>;
        _track = results[2] as List<MachineTrackPoint>;
        _loading = false;
      });
      // Живые значения — фоном; не держим экран на спиннере.
      unawaited(_refreshLiveValues());
    } catch (e) {
      if (!mounted) return;
      if (e is SessionExpiredException) {
        context.go('/login');
        return;
      }
      setState(() {
        _error = auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  /// Ключ API: UUID машины надёжнее IP (IP может быть только в локальном реестре).
  String get _machineApiKey {
    final m = _machine;
    if (m == null) return widget.machineId;
    return m.id;
  }

  Future<void> _refreshLiveValues() async {
    if (!mounted || _sensors.isEmpty) return;
    final gen = ++_liveRefreshGen;
    final repo = CloudScope.of(context).machines;
    final key = _machineApiKey;
    try {
      final live = await repo.getMachineLive(key);
      if (!mounted || gen != _liveRefreshGen) return;
      final journal = AppScope.faultJournalOf(context);
      final deviceLabel = _machine == null
          ? null
          : '${_machine!.code} · ${_machine!.name}';
      final accidentReadings = <LiveSensorReading>[];

      setState(() {
        DateTime? newestPoint;
        for (final reading in live.sensors) {
          final sensor = _sensors
              .where((s) => s.id == reading.id)
              .firstOrNull;
          if (sensor == null) continue;
          if (reading.value == null && reading.fault == null) continue;

          final value = reading.value ?? 0.0;
          final fault = LoopCurrent.faultFromCloud(
            apiFault: reading.fault,
            currentMa: reading.currentMa,
            value: value,
            type: sensor.config.type,
          );
          final currentMa = LoopCurrent.cloudCurrentMa(
            apiCurrentMa: reading.currentMa,
            fault: fault,
            value: value,
            config: sensor.config,
          );

          _liveFaults[sensor.id] = fault;
          _liveCurrentMa[sensor.id] = currentMa;
          _liveValues[sensor.id] =
              fault == LoopFault.none ? value : 0.0;
          _liveStatus[sensor.id] = fault != LoopFault.none
              ? SensorStatusLevel.critical
              : SensorThresholdEvaluator.evaluate(
                  sensor.config,
                  value,
                );

          final liveReading = LiveSensorReading(
            config: sensor.config,
            value: fault == LoopFault.none ? value : 0.0,
            status: _liveStatus[sensor.id]!,
            updatedAt: (reading.ts ?? DateTime.now()).toLocal(),
            loopFault: fault,
            fromDeviceStatus: fault != LoopFault.none,
            currentMa: currentMa,
          );
          if (liveReading.isAccident) {
            accidentReadings.add(liveReading);
          }

          final at = reading.ts;
          if (at != null &&
              (newestPoint == null || at.isAfter(newestPoint))) {
            newestPoint = at;
          }
        }
        if (newestPoint != null) {
          _lastServerPointAt = newestPoint;
        } else if (live.lastSeenAt != null) {
          _lastServerPointAt = live.lastSeenAt;
        }
        _liveUpdatedAt = DateTime.now();
      });

      for (final r in accidentReadings) {
        await journal.maybeRecord(r, deviceLabel: deviceLabel);
      }
    } catch (_) {
      // Сеть/таймаут — значения на шкалах не трогаем, следующий тик повторит.
    }
  }

  static String _liveValueLabel(
    CloudSensor sensor,
    double? live,
    LoopFault fault,
  ) {
    return switch (fault) {
      LoopFault.open => 'обрыв цепи / датчик',
      LoopFault.short => 'короткое замыкание',
      LoopFault.none => live == null
          ? 'Нет свежих данных'
          : SensorDisplayFormat.valueWithUnit(live, sensor.config.unit),
    };
  }

  Future<void> _editMachineDetails() async {
    final machine = _machine;
    if (machine == null) return;

    final codeController = TextEditingController(text: machine.code);
    final nameController = TextEditingController(text: machine.name);
    final operatorController = TextEditingController(
      text: machine.operatorName,
    );
    final locationController = TextEditingController(
      text: machine.locationLabel,
    );
    final descriptionController = TextEditingController(
      text: machine.description,
    );
    final pumpPressureController = TextEditingController(
      text: machine.pumpOnPressureBar.toStringAsFixed(
        machine.pumpOnPressureBar == machine.pumpOnPressureBar.roundToDouble()
            ? 0
            : 1,
      ),
    );
    final pumpTempController = TextEditingController(
      text: machine.pumpOnTemperatureC.toStringAsFixed(
        machine.pumpOnTemperatureC == machine.pumpOnTemperatureC.roundToDouble()
            ? 0
            : 1,
      ),
    );

    Uint8List? pendingPhoto;
    String? pendingMime;
    var clearPhoto = false;
    final existingPhoto = resolveMediaUrl(context, machine.photoUrl);
    final existingPhotoProvider = existingPhoto.isNotEmpty
        ? await authNetworkImageProvider(context, existingPhoto)
        : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Редактировать сведения'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor:
                        Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    backgroundImage: pendingPhoto != null
                        ? MemoryImage(pendingPhoto!)
                        : (!clearPhoto ? existingPhotoProvider : null),
                    child: (pendingPhoto == null &&
                            (clearPhoto || existingPhotoProvider == null))
                        ? const Icon(Icons.precision_manufacturing, size: 36)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                            withData: true,
                          );
                          if (result == null || result.files.isEmpty) return;
                          final file = result.files.first;
                          final bytes = file.bytes;
                          if (bytes == null) return;
                          final ext = (file.extension ?? 'jpg').toLowerCase();
                          final mime = switch (ext) {
                            'png' => 'image/png',
                            'webp' => 'image/webp',
                            _ => 'image/jpeg',
                          };
                          setDialogState(() {
                            pendingPhoto = bytes;
                            pendingMime = mime;
                            clearPhoto = false;
                          });
                        },
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('Фото'),
                      ),
                      if (pendingPhoto != null ||
                          (!clearPhoto && existingPhoto.isNotEmpty))
                        TextButton(
                          onPressed: () => setDialogState(() {
                            pendingPhoto = null;
                            pendingMime = null;
                            clearPhoto = true;
                          }),
                          child: const Text('Убрать'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Код / номер машины',
                      icon: Icon(Icons.tag),
                      helperText: 'Например: 001 вместо длинного ID блока',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название машины',
                      icon: Icon(Icons.precision_manufacturing),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Описание',
                      alignLabelWithHint: true,
                      icon: Icon(Icons.notes_outlined),
                      hintText: 'Цех, назначение, заметки…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: operatorController,
                    decoration: const InputDecoration(
                      labelText: 'Оператор',
                      icon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Локация (цех / адрес)',
                      icon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Насос «вкл»',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Давление выше порога, либо температура выше порога '
                    'при живой линии давления.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pumpPressureController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Порог давления, бар',
                      icon: Icon(Icons.speed),
                      helperText: 'По умолчанию 20',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pumpTempController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Порог температуры, °C',
                      icon: Icon(Icons.thermostat_outlined),
                      helperText: 'По умолчанию 35',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final newCode = codeController.text.trim();
    final newName = nameController.text.trim();
    final newOperator = operatorController.text.trim();
    final newLocation = locationController.text.trim();
    final newDescription = descriptionController.text.trim();
    final pumpPressure = double.tryParse(
      pumpPressureController.text.trim().replaceAll(',', '.'),
    );
    final pumpTemp = double.tryParse(
      pumpTempController.text.trim().replaceAll(',', '.'),
    );

    if (newCode.isEmpty || newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Код и название не могут быть пустыми')),
      );
      return;
    }
    if (pumpPressure == null || pumpTemp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите числовые пороги насоса')),
      );
      return;
    }

    String? photoB64;
    if (pendingPhoto != null && pendingMime != null) {
      photoB64 =
          'data:$pendingMime;base64,${base64Encode(pendingPhoto!)}';
    }

    setState(() => _saving = true);
    final scope = CloudScope.of(context);
    final auth = scope.auth;
    try {
      final updated = await scope.machines.updateMachineDetails(
        _machineApiKey,
        code: newCode,
        name: newName,
        operatorName: newOperator,
        locationLabel: newLocation,
        description: newDescription,
        photoBase64: photoB64,
        clearPhoto: clearPhoto && photoB64 == null,
        pumpOnPressureBar: pumpPressure,
        pumpOnTemperatureC: pumpTemp,
      );
      if (!mounted) return;
      setState(() {
        _machine = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сведения сохранены на сервере')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.humanizeError(e))));
    }
  }

  Future<void> _editCoordinates() async {
    final current = _machine?.gps;
    final latController = TextEditingController(
      text: current?.lat.toStringAsFixed(5) ?? '56.83892',
    );
    final lngController = TextEditingController(
      text: current?.lon.toStringAsFixed(5) ?? '60.60570',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Координаты GPS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Точка с платы появится сама после GPS-фикса (открытое небо, 1–5 мин).\n'
              'Сейчас можно задать широту и долготу вручную.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Широта'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lngController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Долгота'),
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
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final lat = double.tryParse(latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(lngController.text.replaceAll(',', '.'));

    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректные координаты')),
      );
      return;
    }

    setState(() => _saving = true);
    final auth = CloudScope.of(context).auth;
    try {
      final updated = await CloudScope.of(context).machines
          .updateMachineDetails(
            _machineApiKey,
            gps: MachineGps(lat: lat, lon: lng),
          );
      if (!mounted) return;
      setState(() {
        _machine = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Координаты сохранены на сервере')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.humanizeError(e))));
    }
  }

  Future<void> _editGeofence() async {
    final machine = _machine;
    if (machine == null) return;
    final current = machine.geofence;
    final nameController = TextEditingController(
      text: current?.name.isNotEmpty == true ? current!.name : 'Регион ${machine.code}',
    );
    final latController = TextEditingController(
      text: current?.centerLat.toStringAsFixed(5) ??
          machine.gps?.lat.toStringAsFixed(5) ??
          '56.83892',
    );
    final lonController = TextEditingController(
      text: current?.centerLon.toStringAsFixed(5) ??
          machine.gps?.lon.toStringAsFixed(5) ??
          '60.60570',
    );
    final radiusController = TextEditingController(
      text: current?.radiusM.toStringAsFixed(0) ?? '500',
    );
    var enabled = current?.enabled ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Геозона'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Название региона'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Широта центра'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lonController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Долгота центра'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: radiusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Радиус, м'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Геозона активна'),
                  value: enabled,
                  onChanged: (v) => setLocalState(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final lat = double.tryParse(latController.text.replaceAll(',', '.'));
    final lon = double.tryParse(lonController.text.replaceAll(',', '.'));
    final radius = double.tryParse(radiusController.text.replaceAll(',', '.'));
    if (lat == null ||
        lon == null ||
        radius == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180 ||
        radius <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректные параметры геозоны')),
      );
      return;
    }

    setState(() => _saving = true);
    final auth = CloudScope.of(context).auth;
    try {
      final repo = CloudScope.of(context).machines;
      await repo.saveGeofence(
        machine.id,
        MachineGeofence(
          name: nameController.text.trim(),
          centerLat: lat,
          centerLon: lon,
          radiusM: radius,
          enabled: enabled,
        ),
      );
      await _load(silent: true);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Геозона сохранена')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.humanizeError(e))));
    }
  }

  Future<void> _addSensor() async {
    final scope = CloudScope.of(context);
    List<Map<String, dynamic>> catalog;
    try {
      catalog = await scope.machines.fetchSensorCatalog();
    } catch (_) {
      catalog = [
        {'type': 'pressure', 'name': 'Давление'},
        {'type': 'temperature', 'name': 'Температура'},
        {'type': 'flow', 'name': 'Расход'},
        {'type': 'level', 'name': 'Уровень'},
        {'type': 'vibration', 'name': 'Вибрация'},
      ];
    }
    if (!mounted) return;

    // Плата: максимум 6 каналов ADC1 (CH0–CH5).
    final occupied = _sensors.map((s) => s.config.channelIndex).toSet();
    final freeChannels = [
      for (var ch = 0; ch < AppConstants.hardwareAnalogChannels; ch++)
        if (!occupied.contains(ch)) ch,
    ];
    if (freeChannels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'На этой плате до 6 аналоговых каналов (ADC1, CH0–CH5). '
            'Все уже заняты в конфигурации станции.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Добавить датчик'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              _isPlatform
                  ? 'Свободные каналы: '
                      '${freeChannels.map((c) => c + 1).join(', ')}\n'
                      'CH0–CH5 (ADC1): '
                      '1=GPIO35 2=GPIO34 3=GPIO33 4=GPIO32 '
                      '5=GPIO36 6=GPIO39'
                  : 'Свободные каналы: '
                      '${freeChannels.map((c) => c + 1).join(', ')}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          for (final item in catalog)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, item),
              child: Text('${item['name'] ?? item['type']} (${item['type']})'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    int channel = freeChannels.first;
    if (freeChannels.length > 1) {
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Канал на плате'),
          children: [
            for (final ch in freeChannels)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ch),
                child: Text(
                  _isPlatform
                      ? 'Канал ${ch + 1} (GPIO${_gpioForChannel(ch)})'
                      : 'Канал ${ch + 1}',
                ),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      channel = picked;
    }

    setState(() => _saving = true);
    try {
      final created = await scope.machines.addSensor(
        _machineApiKey,
        type: selected['type'] as String,
        name: selected['name'] as String?,
        channelIndex: channel,
      );
      if (!mounted) return;
      if (created != null) {
        setState(() {
          _sensors = [..._sensors, created];
          _saving = false;
        });
        if (_isPlatformAdmin) {
          await _offerEspCalCommands(created);
        }
      } else {
        setState(() => _saving = false);
        await _load(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(scope.auth.humanizeError(e))),
      );
    }
  }

  Future<void> _changeOwner(MachineSummary machine) async {
    if (_isPlatform) {
      await _assignManufacturer(machine);
      return;
    }
    await _transferToClient(machine);
  }

  Future<void> _assignManufacturer(MachineSummary machine) async {
    if (_manufacturers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет производителей в системе')),
      );
      return;
    }

    final maker = await showDialog<ClientOrgSummary>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Назначить производителю'),
        children: _manufacturers
            .map(
              (m) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text(m.name),
              ),
            )
            .toList(),
      ),
    );
    if (maker == null || !mounted) return;

    try {
      await CloudScope.of(context).organizations.assignManufacturer(
        machineId: machine.id,
        manufacturerOrganizationId: maker.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${machine.code} → ${maker.name}')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _transferToClient(MachineSummary machine) async {
    if (_clients.isEmpty) {
      final canCreateFactory = _isPlatform || _isManufacturer;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            canCreateFactory
                ? 'Нет заводов — создайте в настройках'
                : 'Нет заводов — обратитесь к производителю или админу платформы',
          ),
          action: canCreateFactory
              ? SnackBarAction(
                  label: 'Создать',
                  onPressed: () => context.push('/admin/factory'),
                )
              : null,
        ),
      );
      return;
    }

    final client = await showDialog<ClientOrgSummary>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          machine.ownerOrgName == null
              ? 'Передать заводу'
              : 'Сменить владельца (завод)',
        ),
        children: _clients
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text(
                  c.id == machine.organizationId
                      ? '${c.name} (текущий)'
                      : c.name,
                ),
              ),
            )
            .toList(),
      ),
    );
    if (client == null || !mounted) return;
    if (client.id == machine.organizationId) return;

    try {
      await CloudScope.of(context).organizations.transferMachine(
        machineId: machine.id,
        clientOrganizationId: client.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${machine.code} → ${client.name}')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _deleteSensor(CloudSensor sensor) async {
    final ch = sensor.config.channelIndex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать датчик?'),
        content: Text(
          '«${sensor.config.name}» (канал ${ch + 1}) будет удалён '
          'с сервера вместе с историей.\n\n'
          'На плате отключите канал командой:\nDISABLE $ch',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await CloudScope.of(context).machines.deleteSensor(
        _machineApiKey,
        sensor.id,
      );
      if (!mounted) return;
      setState(() {
        _sensors = _sensors.where((s) => s.id != sensor.id).toList();
        _saving = false;
      });
      await Clipboard.setData(ClipboardData(text: 'DISABLE $ch'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Удалён. В Serial вставлено в буфер: DISABLE $ch',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CloudScope.of(context).auth.humanizeError(e)),
        ),
      );
    }
  }

  Future<void> _deleteMachineOnServer() async {
    final machine = _machine;
    if (machine == null || !_isPlatform || !_isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить машину на сервере?'),
        content: Text(
          '${machine.code} · ${machine.name} будет удалена вместе с '
          'датчиками и историей показаний.\nЭто необратимо.\n\n'
          'Чтобы только скрыть из списка, смахните карточку в парке.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await CloudScope.of(context).machines.deleteMachineOnServer(machine.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${machine.code} удалена на сервере')),
      );
      context.go('/fleet');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _editSensor(CloudSensor sensor) async {
    final result = await context.push<bool>(
      '/sensors/thresholds/${widget.machineId}?focus=${Uri.encodeComponent(sensor.id)}',
    );
    if (!mounted) return;
    if (result == true || result == null) {
      // Обновляем список после возврата (сохранение или просто назад).
      await _load(silent: true);
    }
  }

  /// Шкала 4–20 мА живёт на плате (NVS). Тип в приложении сам плату не калибрует.
  String _espCalCommands(SensorConfig config) {
    final ch = config.channelIndex;
    final min = config.scaleMin;
    final max = config.scaleMax;
    return 'ENABLE $ch\n'
        'CAL $ch ${min.toStringAsFixed(min == min.roundToDouble() ? 0 : 1)} '
        '${max.toStringAsFixed(max == max.roundToDouble() ? 0 : 1)}\n'
        'SHOW';
  }

  Future<void> _offerEspCalCommands(CloudSensor sensor) async {
    if (!mounted || !_isPlatformAdmin) return;
    // Если шкала «пустая»/давление по умолчанию на temp — подставим пресет типа.
    var cfg = sensor.config;
    if (cfg.type == SensorType.temperature &&
        cfg.scaleMin == 0 &&
        cfg.scaleMax >= 200) {
      final preset = SensorConfig.defaults(cfg.channelIndex, SensorType.temperature);
      cfg = cfg.copyWith(scaleMin: preset.scaleMin, scaleMax: preset.scaleMax);
    }
    final text = _espCalCommands(cfg);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Калибровка платы: ${cfg.name}'),
        content: SelectableText(
          'Тип в приложении ≠ шкала на плате.\n'
          'Команды скопированы — вставьте в Serial (115200):\n\n'
          '$text\n\n'
          'Канал приложения ${cfg.channelIndex + 1} = CAL ${cfg.channelIndex}'
          '${_isPlatform ? ' (GPIO${_gpioForChannel(cfg.channelIndex)})' : ''}.\n'
          'Если в мониторе ~0 mA — сначала проверьте проводку 4–20 мА.',
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Машина')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ),
      );
    }

    final machine = _machine;
    if (machine == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Машина не найдена')),
      );
    }

    final canConfigure = _isAdmin && machine.canConfigure;
    final canDeleteOnServer = _isAdmin && _isPlatform;
    final canChangeOwner =
        _isAdmin && machine.canReassign && (_isManufacturer || _isPlatform);
    final scheme = Theme.of(context).colorScheme;
    final statusColor = machineStatusColor(machine.status, scheme);
    final lastSeen = machine.lastSeenAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(machine.lastSeenAt!.toLocal())
        : '—';

    return Scaffold(
      appBar: AppBar(
        title: Text(machine.code),
        actions: [
          if (canConfigure)
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: 'Редактировать сведения',
              onPressed: _saving ? null : _editMachineDetails,
            ),
          if (canDeleteOnServer)
            PopupMenuButton<String>(
              enabled: !_saving,
              onSelected: (value) {
                if (value == 'delete') _deleteMachineOnServer();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Удалить на сервере',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ==========================================
                // КАРТОЧКА НАЗВАНИЯ И МОДЕЛИ
                // ==========================================
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Builder(
                      builder: (context) {
                        final photo = resolveMediaUrl(
                          context,
                          machine.photoUrl,
                        );
                        if (photo.isNotEmpty) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AuthNetworkImage(
                              url: photo,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.precision_manufacturing,
                                color: statusColor,
                                size: 36,
                              ),
                            ),
                          );
                        }
                        return Icon(
                          Icons.precision_manufacturing,
                          color: statusColor,
                          size: 36,
                        );
                      },
                    ),
                    title: Text(
                      machine.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (machine.model.trim().isNotEmpty)
                          'Модель: ${machine.model}',
                        if (machine.description.trim().isNotEmpty)
                          machine.description.trim(),
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: machine.description.trim().isNotEmpty,
                    trailing: canConfigure
                        ? const Icon(Icons.edit_outlined, size: 18)
                        : null,
                    onTap: canConfigure ? _editMachineDetails : null,
                  ),
                ),
                const SizedBox(height: 12),

                // ==========================================
                // ПАНЕЛЬ ХАРАКТЕРИСТИК И ВРЕМЕНИ РАБОТЫ (Uptime)
                // ==========================================
                Card(
                  elevation: 0,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatBlock(
                                context,
                                icon: Icons.power_settings_new,
                                title: 'Время работы',
                                value: formatCumulativeDuration(
                                  machine.uptimeHours,
                                ),
                                color: scheme.primary,
                              ),
                            ),
                            Expanded(
                              child: _buildStatBlock(
                                context,
                                icon: Icons.speed,
                                title: 'Моточасы',
                                value: formatMotorHours(
                                  machine.engineHours,
                                ),
                                color: scheme.tertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatBlock(
                                context,
                                icon: Icons.water_drop_outlined,
                                title: 'Работа насоса',
                                value: formatCumulativeDuration(
                                  machine.pumpHours,
                                ),
                                color: scheme.secondary,
                              ),
                            ),
                            Expanded(
                              child: _buildStatBlock(
                                context,
                                icon: Icons.play_circle_outline,
                                title: 'Запусков насоса',
                                value: '${machine.pumpStarts ?? 0}',
                                color: scheme.outline,
                              ),
                            ),
                            Expanded(
                              child: _buildStatBlock(
                                context,
                                icon: Icons.circle,
                                title: 'Статус',
                                value: machineStatusLabel(machine.status),
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (machine.headlineAlert != null) ...[
                  Card(
                    color: statusColor.withValues(alpha: 0.1),
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: statusColor),
                      title: Text(machine.headlineAlert!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ==========================================
                // ИНФОРМАЦИОННЫЕ ПОЛЯ (Локация и Оператор)
                // ==========================================
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: const Text('Локация'),
                        subtitle: Text(
                          machine.locationLabel.isEmpty
                              ? 'Не указана'
                              : machine.locationLabel,
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Оператор'),
                        subtitle: Text(
                          machine.operatorName.isEmpty
                              ? 'Не назначен'
                              : machine.operatorName,
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('Последняя активность'),
                        subtitle: Text(lastSeen),
                      ),
                    ],
                  ),
                ),

                if (machine.ownerOrgName != null || canChangeOwner) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.factory_outlined),
                    title: Text(
                      _isPlatform ? 'Производитель / владелец' : 'Владелец',
                    ),
                    subtitle: Text(
                      machine.ownerOrgName ??
                          (_isPlatform
                              ? 'Не назначен производителю'
                              : 'Склад производителя'),
                    ),
                    trailing: canChangeOwner
                        ? IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: _isPlatform
                                ? 'Назначить производителю'
                                : 'Сменить завод',
                            onPressed: _saving
                                ? null
                                : () => _changeOwner(machine),
                          )
                        : null,
                    onTap: canChangeOwner && !_saving
                        ? () => _changeOwner(machine)
                        : null,
                  ),
                ],
                if (machine.isReadOnlyForCurrentUser)
                  const ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('Режим производителя'),
                    subtitle: Text(
                      'Конфигурация у завода — можно сменить владельца',
                    ),
                  ),

                if (canChangeOwner && machine.ownerOrgName == null) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _changeOwner(machine),
                    icon: Icon(
                      _isPlatform
                          ? Icons.precision_manufacturing_outlined
                          : Icons.local_shipping_outlined,
                    ),
                    label: Text(
                      _isPlatform
                          ? 'Назначить производителю'
                          : 'Передать заводу',
                    ),
                  ),
                ],

                // ==========================================
                // БЛОК ДАТЧИКОВ
                // ==========================================
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Датчики',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Всего: ${_sensors.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (canConfigure) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Добавить датчик',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _addSensor,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isPlatformAdmin && _liveUpdatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Опрос приложения: каждые '
                      '${_boundPollSeconds ?? _telemetry?.pollSeconds ?? AppConstants.defaultPollSeconds} с '
                      '(последний ${DateFormat('HH:mm:ss').format(_liveUpdatedAt!)})'
                      '${_lastServerPointAt != null ? ' · точка с платы ${DateFormat('HH:mm:ss').format(_lastServerPointAt!)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_sensors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('Нет датчиков в конфигурации.')),
                  )
                else
                  ..._sensors.where((s) {
                    if (s.config.enabled) return true;
                    return canConfigure;
                  }).map((s) {
                    final live = _liveValues[s.id];
                    final fault = _liveFaults[s.id] ?? LoopFault.none;
                    final status =
                        _liveStatus[s.id] ?? SensorStatusLevel.offline;
                    final gaugeValue = fault != LoopFault.none
                        ? s.config.scaleMin
                        : (live ?? s.config.scaleMin);
                    return Card(
                      child: InkWell(
                        onTap: () => showCloudSensorDayChartPopup(
                          context,
                          machineId: machine.id,
                          sensorId: s.id,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Row(
                            children: [
                              CircularSensorGauge(
                                value: gaugeValue,
                                config: s.config,
                                status: live == null && fault == LoopFault.none
                                    ? SensorStatusLevel.offline
                                    : status,
                                size: 88,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.config.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${s.config.type.label} · канал '
                                      '${s.config.channelIndex + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _liveValueLabel(s, live, fault),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: live == null &&
                                                    fault == LoopFault.none
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                : AppTheme.statusColor(
                                                    status,
                                                    context,
                                                  ),
                                          ),
                                    ),
                                    if (fault != LoopFault.none ||
                                        _liveCurrentMa[s.id] != null)
                                      Text(
                                        'Петля 4–20 мА: ${LoopCurrent.formatMa(_liveCurrentMa[s.id], fault: fault)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    Text(
                                      'Норма: ${s.config.normMin ?? s.config.scaleMin}'
                                      '–${s.config.normMax} ${s.config.unit}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (canConfigure || _isPlatformAdmin)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isPlatformAdmin)
                                      IconButton(
                                        icon: const Icon(Icons.usb, size: 20),
                                        tooltip: 'CAL для платы',
                                        onPressed: () => _offerEspCalCommands(s),
                                      ),
                                    if (canConfigure) ...[
                                      IconButton(
                                        icon: const Icon(Icons.tune, size: 20),
                                        tooltip: 'Изменить пороги',
                                        onPressed: () => _editSensor(s),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        tooltip: 'Убрать с экрана',
                                        onPressed: _saving
                                            ? null
                                            : () => _deleteSensor(s),
                                      ),
                                    ],
                                  ],
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.show_chart,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                // ==========================================
                // КАРТА МЕСТОПОЛОЖЕНИЯ (OpenStreetMap)
                // ==========================================
                const SizedBox(height: 20),
                Text(
                  'Геопозиция',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                MachineLocationMapCard(
                  gps: machine.gps,
                  track: _track,
                  geofence: machine.geofence,
                  machineCode: machine.code,
                  canEdit: canConfigure || _isAdmin,
                  onEdit: _editCoordinates,
                  onOpenFleetMap: () => context.push('/fleet/map'),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _editGeofence,
                      icon: const Icon(Icons.radar, size: 18),
                      label: Text(
                        machine.geofence == null
                            ? 'Настроить регион'
                            : 'Изменить регион',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('НАЗАД К ПАРКУ'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
          if (_saving)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  int _gpioForChannel(int channel) => AppConstants.gpioForChannel(channel);
}
