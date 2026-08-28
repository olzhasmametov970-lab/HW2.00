/// UUID GATT HydroWin (совпадают с firmware/esp32_ingest/config.h).
abstract final class BleUuids {
  static const service = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const rxWrite = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const txNotify = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Advertise: `HydroWin1` / `HydroWin-…` / любой `HydroWin…`.
  static const advertisePrefix = 'HydroWin';
}
