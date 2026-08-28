/// Форматирует накопленные часы как «3 дн. 7 ч» (не сбрасывается по дням).
String formatCumulativeDuration(double? hours) {
  if (hours == null || hours <= 0) return '0 ч';
  final totalMinutes = (hours * 60).round();
  final days = totalMinutes ~/ (24 * 60);
  final rem = totalMinutes % (24 * 60);
  final hrs = rem ~/ 60;
  final mins = rem % 60;

  if (days > 0) {
    if (hrs > 0) return '$days дн. $hrs ч';
    return '$days дн.';
  }
  if (hrs > 0) {
    if (mins > 0) return '$hrs ч $mins мин';
    return '$hrs ч';
  }
  return '$mins мин';
}

/// Моточасы — только в часах, без перевода в дни.
String formatMotorHours(double? hours) {
  if (hours == null || hours <= 0) return '0 ч';
  if (hours >= 10) return '${hours.round()} ч';
  return '${hours.toStringAsFixed(1)} ч';
}
