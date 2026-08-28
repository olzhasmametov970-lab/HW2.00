import 'package:hydrowin/core/ble/crc8_maxim.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

/// Распарсенный BLE-пакет (v2: CH0–CH5 / 21 байт; v1: CH0–CH2 / 14 байт).
class TelemetryPacket {
  const TelemetryPacket({
    required this.protoVersion,
    required this.timestamp,
    required this.channels,
    required this.gpsValid,
  });

  final int protoVersion;
  final DateTime timestamp;
  final List<ChannelReading> channels;
  final bool gpsValid;

  static TelemetryPacket? tryParse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final proto = bytes[0];

    if (proto == AppConstants.telemetryProtoVersion &&
        bytes.length >= AppConstants.telemetryPacketLength) {
      return _parseV2(bytes);
    }
    if (proto == AppConstants.telemetryProtoVersionV1 &&
        bytes.length >= AppConstants.telemetryPacketLengthV1) {
      return _parseV1(bytes);
    }
    return null;
  }

  /// v2: 21 байт, CH0–CH5, status в байтах 18–19.
  static TelemetryPacket? _parseV2(List<int> bytes) {
    final expectedCrc = bytes[20];
    final actualCrc = crc8Maxim(bytes.sublist(0, 20));
    if (expectedCrc != actualCrc) return null;

    final flags = bytes[1];
    final tsSec = bytes[2] |
        (bytes[3] << 8) |
        (bytes[4] << 16) |
        (bytes[5] << 24);

    final statusWord = bytes[18] | (bytes[19] << 8);
    final channels = <ChannelReading>[];
    for (var i = 0; i < AppConstants.telemetryChannelCount; i++) {
      channels.add(_decodeChannel(bytes, 6 + i * 2, statusWord, i));
    }

    return TelemetryPacket(
      protoVersion: AppConstants.telemetryProtoVersion,
      gpsValid: (flags & 1) != 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsSec * 1000, isUtc: true)
          .toLocal(),
      channels: channels,
    );
  }

  /// v1: 14 байт, CH0–CH2 (старые платы).
  static TelemetryPacket? _parseV1(List<int> bytes) {
    final expectedCrc = bytes[13];
    final actualCrc = crc8Maxim(bytes.sublist(0, 13));
    if (expectedCrc != actualCrc) return null;

    final flags = bytes[1];
    final tsSec = bytes[2] |
        (bytes[3] << 8) |
        (bytes[4] << 16) |
        (bytes[5] << 24);

    final statusByte = bytes[12];
    return TelemetryPacket(
      protoVersion: AppConstants.telemetryProtoVersionV1,
      gpsValid: (flags & 1) != 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsSec * 1000, isUtc: true)
          .toLocal(),
      channels: [
        _decodeChannel(bytes, 6, statusByte, 0),
        _decodeChannel(bytes, 8, statusByte, 1),
        _decodeChannel(bytes, 10, statusByte, 2),
      ],
    );
  }

  static ChannelReading _decodeChannel(
    List<int> bytes,
    int offset,
    int statusBits,
    int index,
  ) {
    final raw = bytes[offset] | (bytes[offset + 1] << 8);
    final signed = raw > 0x7FFF ? raw - 0x10000 : raw;
    final value = signed / 10.0;
    final levelBits = (statusBits >> (index * 2)) & 0x3;
    // Прошивка: 2 = КЗ, 3 = обрыв; оба → critical в UI.
    final loopFault = switch (levelBits) {
      2 => LoopFault.short,
      3 => LoopFault.open,
      _ => LoopFault.none,
    };
    final level = switch (levelBits) {
      1 => SensorStatusLevel.warning,
      2 || 3 => SensorStatusLevel.critical,
      _ => SensorStatusLevel.ok,
    };
    return ChannelReading(
      channelIndex: index,
      value: value,
      level: level,
      loopFault: loopFault,
    );
  }
}

enum LoopFault { none, open, short }

class ChannelReading {
  const ChannelReading({
    required this.channelIndex,
    required this.value,
    required this.level,
    this.loopFault = LoopFault.none,
  });

  final int channelIndex;
  final double value;
  final SensorStatusLevel level;
  final LoopFault loopFault;
}
