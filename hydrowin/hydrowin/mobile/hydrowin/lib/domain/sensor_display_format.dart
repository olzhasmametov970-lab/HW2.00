/// Формат показаний для UI: целые числа («7 бар», «28 °C»).
abstract final class SensorDisplayFormat {
  static String valueWithUnit(double value, String unit) {
    final v = value.round();
    final u = unit.trim();
    if (u.isEmpty) return '$v';
    return '$v $u';
  }
}
