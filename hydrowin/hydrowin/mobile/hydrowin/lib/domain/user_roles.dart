/// Роли пользователей облачного режима (совпадают с backend `app/roles.py`).
abstract final class UserRoles {
  static const orgAdmin = 'org_admin';
  static const driver = 'driver';

  static bool isAdmin(String? role) => role == orgAdmin;

  static bool isDriver(String? role) => role == driver;

  static bool canConfigureHardware(String? role) => isAdmin(role);

  /// Админ завода или админ платформы может создавать водителей.
  static bool canCreateDriver({
    required bool isAdmin,
    required bool isClientOrg,
    required bool isPlatformOrg,
  }) =>
      isAdmin && (isClientOrg || isPlatformOrg);

  static String label(String? role) {
    return switch (role) {
      orgAdmin => 'Администратор',
      driver => 'Водитель',
      _ => role ?? '—',
    };
  }
}
