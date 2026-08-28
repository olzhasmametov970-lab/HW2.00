/// CRC-8/MAXIM для BLE-пакета (bytes 0..length-1).
int crc8Maxim(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0x8C;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFF;
}
