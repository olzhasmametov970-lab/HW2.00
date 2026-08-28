import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/ble/crc8_maxim.dart';
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/core/theme/app_theme.dart';

void main() {
  test('parses valid 21-byte v2 packet CH0–CH5', () {
    final packet = _samplePacketV2(
      values: [1453, 428, 125, 1000, 50, 75],
      status: 0,
    );

    final parsed = TelemetryPacket.tryParse(packet);
    expect(parsed, isNotNull);
    expect(parsed!.channels, hasLength(6));
    expect(parsed.channels[0].value, closeTo(145.3, 0.01));
    expect(parsed.channels[1].value, closeTo(42.8, 0.01));
    expect(parsed.channels[2].value, closeTo(12.5, 0.01));
    expect(parsed.channels[3].value, closeTo(100.0, 0.01));
    expect(parsed.channels[4].value, closeTo(5.0, 0.01));
    expect(parsed.channels[5].value, closeTo(7.5, 0.01));
    expect(parsed.channels.every((c) => c.level == SensorStatusLevel.ok), isTrue);
  });

  test('rejects wrong CRC on v2', () {
    final packet = _samplePacketV2(
      values: [1000, 200, 300, 0, 0, 0],
      status: 0,
    );
    packet[20] = 0xFF;
    expect(TelemetryPacket.tryParse(packet), isNull);
  });

  test('decodes warning status bits on ch1', () {
    // ch1 warning = bits 2–3 = 01 → 0x04
    final packet = _samplePacketV2(
      values: [500, 520, 100, 0, 0, 0],
      status: 0x04,
    );
    final parsed = TelemetryPacket.tryParse(packet)!;
    expect(parsed.channels[1].level, SensorStatusLevel.warning);
  });

  test('still parses legacy 14-byte v1 packet', () {
    final bytes = List<int>.filled(14, 0);
    bytes[0] = 0x01;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    bytes[2] = ts & 0xFF;
    bytes[3] = (ts >> 8) & 0xFF;
    bytes[4] = (ts >> 16) & 0xFF;
    bytes[5] = (ts >> 24) & 0xFF;
    _writeInt16Le(bytes, 6, 1453);
    _writeInt16Le(bytes, 8, 428);
    _writeInt16Le(bytes, 10, 125);
    bytes[12] = 0;
    bytes[13] = crc8Maxim(bytes.sublist(0, 13));

    final parsed = TelemetryPacket.tryParse(bytes);
    expect(parsed, isNotNull);
    expect(parsed!.protoVersion, AppConstants.telemetryProtoVersionV1);
    expect(parsed.channels, hasLength(3));
    expect(parsed.channels[0].value, closeTo(145.3, 0.01));
  });
}

List<int> _samplePacketV2({
  required List<int> values,
  required int status,
}) {
  final bytes = List<int>.filled(AppConstants.telemetryPacketLength, 0);
  bytes[0] = AppConstants.telemetryProtoVersion;
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  bytes[2] = ts & 0xFF;
  bytes[3] = (ts >> 8) & 0xFF;
  bytes[4] = (ts >> 16) & 0xFF;
  bytes[5] = (ts >> 24) & 0xFF;
  for (var i = 0; i < AppConstants.telemetryChannelCount; i++) {
    final v = i < values.length ? values[i] : 0;
    _writeInt16Le(bytes, 6 + i * 2, v);
  }
  bytes[18] = status & 0xFF;
  bytes[19] = (status >> 8) & 0xFF;
  bytes[20] = crc8Maxim(bytes.sublist(0, 20));
  return bytes;
}

void _writeInt16Le(List<int> bytes, int offset, int value) {
  final v = value & 0xFFFF;
  bytes[offset] = v & 0xFF;
  bytes[offset + 1] = (v >> 8) & 0xFF;
}
