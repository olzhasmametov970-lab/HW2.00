import 'package:hydrowin/core/constants/app_constants.dart';

class NetworkSettings {
  const NetworkSettings({
    this.BLOCKLinkType = AppConstants.BLOCKLinkAuto,
    this.wifiSsid = '',
    this.wifiPassword = '',
    this.gsmApn = 'internet.mts.ru',
    this.gsmApnUser = 'mts',
    this.gsmApnPass = 'mts',
    this.selectedMachineId = '',
    this.selectedDeviceId = '',
    this.deviceKey = '',
  });

  /// Как блок передаёт данные: wifi | gsm | auto (failover).
  final String BLOCKLinkType;
  final String wifiSsid;
  final String wifiPassword;
  final String gsmApn;
  final String gsmApnUser;
  final String gsmApnPass;

  /// Какую машину/плату сейчас настраиваем (для USB-команд).
  final String selectedMachineId;
  final String selectedDeviceId;
  final String deviceKey;

  bool get isWifi => BLOCKLinkType == AppConstants.BLOCKLinkWifi;
  bool get isGsm => BLOCKLinkType == AppConstants.BLOCKLinkGsm;
  bool get isAuto => BLOCKLinkType == AppConstants.BLOCKLinkAuto;

  String get linkTypeLabel {
    if (isGsm) return 'GSM (SIM)';
    if (isAuto) return 'Auto (Wi‑Fi ↔ GSM)';
    return 'Wi‑Fi';
  }

  NetworkSettings copyWith({
    String? BLOCKLinkType,
    String? wifiSsid,
    String? wifiPassword,
    String? gsmApn,
    String? gsmApnUser,
    String? gsmApnPass,
    String? selectedMachineId,
    String? selectedDeviceId,
    String? deviceKey,
  }) {
    return NetworkSettings(
      BLOCKLinkType: BLOCKLinkType ?? this.BLOCKLinkType,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
      gsmApn: gsmApn ?? this.gsmApn,
      gsmApnUser: gsmApnUser ?? this.gsmApnUser,
      gsmApnPass: gsmApnPass ?? this.gsmApnPass,
      selectedMachineId: selectedMachineId ?? this.selectedMachineId,
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      deviceKey: deviceKey ?? this.deviceKey,
    );
  }

  /// USB-команды для Serial Monitor платы (115200).
  String toBlockUsbCommands({
    required String apiHost,
    required int apiPort,
  }) {
    final link = isGsm
        ? 'gsm'
        : (isAuto ? 'auto' : 'wifi');
    final buf = StringBuffer()
      ..writeln('LINK $link')
      ..writeln('API $apiHost|$apiPort');
    if (selectedMachineId.trim().isNotEmpty) {
      buf.writeln('MACHINE ${selectedMachineId.trim()}');
    }
    if (selectedDeviceId.trim().isNotEmpty) {
      buf.writeln('DEVICE ${selectedDeviceId.trim()}');
    }
    if (deviceKey.trim().isNotEmpty) {
      buf.writeln('KEY ${deviceKey.trim()}');
    }
    if (wifiSsid.trim().isNotEmpty) {
      buf.writeln('WIFI ${wifiSsid.trim()}|$wifiPassword');
    }
    if (gsmApn.trim().isNotEmpty) {
      buf.writeln(
        'GSM ${gsmApn.trim()}|${gsmApnUser.trim()}|$gsmApnPass',
      );
    }
    buf.writeln('CFG');
    return buf.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'BLOCK_link_type': BLOCKLinkType,
        'wifi_ssid': wifiSsid,
        'wifi_password': wifiPassword,
        'gsm_apn': gsmApn,
        'gsm_apn_user': gsmApnUser,
        'gsm_apn_pass': gsmApnPass,
        'selected_machine_id': selectedMachineId,
        'selected_device_id': selectedDeviceId,
        'device_key': deviceKey,
      };

  factory NetworkSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['block_link_type'] as String? ?? AppConstants.BLOCKLinkAuto;
    final link = (raw == AppConstants.BLOCKLinkWifi ||
            raw == AppConstants.BLOCKLinkGsm ||
            raw == AppConstants.BLOCKLinkAuto)
        ? raw
        : AppConstants.BLOCKLinkAuto;
    return NetworkSettings(
      BLOCKLinkType: link,
      wifiSsid: json['wifi_ssid'] as String? ?? '',
      wifiPassword: json['wifi_password'] as String? ?? '',
      gsmApn: json['gsm_apn'] as String? ?? 'internet.mts.ru',
      gsmApnUser: json['gsm_apn_user'] as String? ?? 'mts',
      gsmApnPass: json['gsm_apn_pass'] as String? ?? 'mts',
      selectedMachineId: json['selected_machine_id'] as String? ?? '',
      selectedDeviceId: json['selected_device_id'] as String? ?? '',
      deviceKey: json['device_key'] as String? ?? '',
    );
  }
}
