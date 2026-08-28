enum SensorType {
  pressure,
  temperature,
  flow,
  level,
  vibration,
  custom;

  String get label => switch (this) {
        SensorType.pressure => 'Давление',
        SensorType.temperature => 'Температура',
        SensorType.flow => 'Расход',
        SensorType.level => 'Уровень',
        SensorType.vibration => 'Вибрация',
        SensorType.custom => 'Другой',
      };

  String get unit => switch (this) {
        SensorType.pressure => 'бар',
        SensorType.temperature => '°C',
        SensorType.flow => 'л/мин',
        SensorType.level => '%',
        SensorType.vibration => 'мм/с',
        SensorType.custom => '',
      };

  static SensorType fromApi(String value) {
    return SensorType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => SensorType.custom,
    );
  }
}
