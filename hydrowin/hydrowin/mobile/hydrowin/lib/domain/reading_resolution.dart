/// Описание шага агрегации показаний на сервере (см. backend time_bucket / archive).
abstract final class ReadingResolution {
  /// Максимум истории на сервере (агрегаты hourly/daily).
  static const maxHistoryDays = 180;

  /// Сырые точки хранятся столько дней.
  static const rawHistoryDays = 30;

  static String describeSpan(Duration span) {
    final minutes = span.inMinutes.clamp(1, maxHistoryDays * 24 * 60);
    if (minutes <= 60) {
      return 'все записи (без усреднения)';
    }
    if (minutes <= 1440) {
      return 'усреднение по 1 минуте';
    }
    if (minutes <= 10080) {
      return 'усреднение по 1 часу';
    }
    if (minutes <= 45 * 24 * 60) {
      return 'усреднение по 1 часу (архив)';
    }
    return 'усреднение по 1 дню (архив)';
  }

  static int estimatedPointCount(Duration span) {
    final minutes = span.inMinutes.clamp(1, maxHistoryDays * 24 * 60);
    if (minutes <= 60) return minutes * 2;
    if (minutes <= 1440) return (minutes / 1).ceil();
    if (minutes <= 45 * 24 * 60) return (minutes / 60).ceil();
    return (minutes / 1440).ceil();
  }
}
