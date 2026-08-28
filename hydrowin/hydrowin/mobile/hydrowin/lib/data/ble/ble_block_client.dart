import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hydrowin/core/ble/ble_uuids.dart';
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:permission_handler/permission_handler.dart';

class BleDiscoveredBlock {
  const BleDiscoveredBlock({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

class BleBlockClient {
  final _devicesCtrl = StreamController<List<BleDiscoveredBlock>>.broadcast();
  final _textCtrl = StreamController<String>.broadcast();
  final _packetCtrl = StreamController<TelemetryPacket>.broadcast();

  final Map<String, ScanResult> _scanCache = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxWrite;

  bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isWindows);
  Stream<List<BleDiscoveredBlock>> get devices => _devicesCtrl.stream;
  Stream<String> get textMessages => _textCtrl.stream;
  Stream<TelemetryPacket> get packets => _packetCtrl.stream;

  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    _ensureSupported();
    await _requestPermissions();

    if (await FlutterBluePlus.isSupported == false) {
      throw StateError('Bluetooth на устройстве не поддерживается');
    }
    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      throw StateError(
        Platform.isWindows
            ? 'Включите Bluetooth в параметрах Windows'
            : 'Включите Bluetooth на устройстве',
      );
    }

    _scanCache.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!_isHydroWinScanResult(result)) continue;
        _scanCache[result.device.remoteId.str] = result;
      }

      final list = _scanCache.values
          .map(
            (r) => BleDiscoveredBlock(
              id: r.device.remoteId.str,
              name: _displayName(r),
              rssi: r.rssi,
            ),
          )
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _devicesCtrl.add(list);
    });

    await FlutterBluePlus.stopScan();
    // Без OS-фильтра withServices: имя/UUID могут не попасть в 31 байт advertise.
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );
    await Future<void>.delayed(timeout + const Duration(milliseconds: 250));
    await FlutterBluePlus.stopScan();
  }

  /// На Android имя часто только в advertise (`advName`), а `platformName` пустой
  /// до первого connect — из‑за этого старый фильтр пропускал все HydroWin-*.
  static String _scanName(ScanResult result) {
    final adv = result.advertisementData.advName.trim();
    if (adv.isNotEmpty) return adv;
    final cachedAdv = result.device.advName.trim();
    if (cachedAdv.isNotEmpty) return cachedAdv;
    return result.device.platformName.trim();
  }

  /// Хвост MAC: B4:BF:E9:11:9D:42 → 9D42
  static String shortMacTail(String remoteId) {
    final parts = remoteId
        .toUpperCase()
        .split(RegExp(r'[:\-]'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}${parts[parts.length - 1]}';
    }
    final compact = remoteId.toUpperCase().replaceAll(RegExp(r'[^A-F0-9]'), '');
    if (compact.length >= 4) {
      return compact.substring(compact.length - 4);
    }
    return compact;
  }

  static String _displayName(ScanResult result) {
    final name = _scanName(result);
    if (name.isNotEmpty) return name;
    final tail = shortMacTail(result.device.remoteId.str);
    return tail.isEmpty
        ? 'HydroWin-${result.device.remoteId.str}'
        : 'HydroWin-$tail';
  }

  static bool _isHydroWinScanResult(ScanResult result) {
    final name = _scanName(result);
    // Firmware: "HydroWin1"; раньше: "HydroWin-<DEVICE_ID>"
    if (name.startsWith(BleUuids.advertisePrefix)) return true;
    return result.advertisementData.serviceUuids.any(
      (u) => u.str128.toLowerCase() == BleUuids.service.toLowerCase(),
    );
  }

  Future<void> connect(String id, {int? rssi}) async {
    _ensureSupported();

    final result = _scanCache[id];
    final device = result?.device ?? BluetoothDevice.fromId(id);

    await FlutterBluePlus.stopScan();
    await disconnect();
    // Windows часто держит прошлую GATT-сессию — пауза перед reconnect.
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    final weakSignal = rssi != null && rssi < -75;
    Object? lastError;
    final attempts = Platform.isWindows ? 3 : 1;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await device.connect(
          license: License.nonprofit,
          timeout: Duration(seconds: Platform.isWindows ? 20 : 15),
          autoConnect: false,
        );
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        if (attempt < attempts) {
          try {
            await device.disconnect();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }
    if (lastError != null) {
      final signalHint = weakSignal
          ? 'Слабый сигнал ($rssi dBm) — поднесите устройство к плате на 0.5–1 м. '
          : '';
      throw StateError(
        '${signalHint}Не удалось подключиться к блоку ($lastError). '
        'Отключите телефон от платы, перезапустите Bluetooth в Windows '
        'и повторите скан.',
      );
    }

    List<BluetoothService> services;
    try {
      services = await device.discoverServices();
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}
      throw StateError('Не удалось прочитать BLE-сервисы платы ($e)');
    }

    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final service in services) {
      if (!_uuidEquals(service.uuid, BleUuids.service)) continue;
      for (final characteristic in service.characteristics) {
        if (_uuidEquals(characteristic.uuid, BleUuids.rxWrite)) {
          rx = characteristic;
        } else if (_uuidEquals(characteristic.uuid, BleUuids.txNotify)) {
          tx = characteristic;
        }
      }
    }

    if (rx == null || tx == null) {
      await device.disconnect();
      throw StateError('BLE сервис HydroWin не найден');
    }

    await tx.setNotifyValue(true);
    await _notifySub?.cancel();
    _notifySub = tx.lastValueStream.listen(_handleNotifyValue);

    _device = device;
    _rxWrite = rx;
  }

  Future<void> writeLine(String line) async {
    final rx = _rxWrite;
    if (rx == null) {
      throw StateError('Сначала подключитесь к блоку');
    }
    final payload = utf8.encode('$line\n');
    await rx.write(payload, withoutResponse: rx.properties.writeWithoutResponse);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _rxWrite = null;

    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _scanSub?.cancel();
    await _devicesCtrl.close();
    await _textCtrl.close();
    await _packetCtrl.close();
  }

  void _handleNotifyValue(List<int> bytes) {
    if (bytes.isEmpty) return;
    final packet = TelemetryPacket.tryParse(bytes);
    if (packet != null) {
      _packetCtrl.add(packet);
      return;
    }

    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isNotEmpty) {
      _textCtrl.add(text);
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final permissions = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];
      final statuses = await permissions.request();
      final denied = statuses.entries
          .where((entry) => !entry.value.isGranted)
          .map((entry) => entry.key)
          .toList();
      if (denied.isNotEmpty) {
        throw StateError('Нужны разрешения Bluetooth и геолокации');
      }
      return;
    }

    if (Platform.isIOS) {
      // iOS: диалог также триггерит CBCentralManager при первом скане.
      final bt = await Permission.bluetooth.request();
      if (bt.isPermanentlyDenied) {
        throw StateError(
          'Bluetooth запрещён. Включите его в Настройки → ГидроВин',
        );
      }
    }
  }

  bool _uuidEquals(Guid actual, String expected) =>
      actual.str128.toLowerCase() == expected.toLowerCase();

  void _ensureSupported() {
    if (!isSupported) {
      throw UnsupportedError(
        'BLE доступен на Android, iOS и Windows (WinRT)',
      );
    }
  }
}
