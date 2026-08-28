/// Исключение при истечении сессии (неудачный refresh).
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'SessionExpiredException';
}
