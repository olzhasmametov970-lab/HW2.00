import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';
import 'package:hydrowin/domain/models/cloud_user.dart';

class OrganizationsRepository {
  OrganizationsRepository(this._get, this._post, this._put, this._delete);

  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, String>? query,
  })
  _get;

  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? body,
  })
  _post;

  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? body,
  })
  _put;

  final Future<void> Function(String path) _delete;

  Future<OrgMeResponse> fetchMe() async {
    if (DemoSession.isActive) return DemoFleetData.orgMe();
    final json = await _get('/orgs/me');
    return OrgMeResponse.fromJson(json);
  }

  Future<CloudUser> fetchMyUser() async {
    if (DemoSession.isActive) return DemoFleetData.currentUser();
    final json = await _get('/orgs/me');
    final user = json['user'];
    if (user is! Map<String, dynamic>) {
      throw StateError('Профиль пользователя недоступен');
    }
    return CloudUser.fromJson(user);
  }

  Future<CloudUser> updateMyProfile({
    String? firstName,
    String? lastName,
    String? birthDate,
    String? gender,
    String? phone,
    String? about,
    String? avatarBase64,
    bool clearAvatar = false,
  }) async {
    if (DemoSession.isActive) return DemoFleetData.currentUser();
    final body = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (birthDate != null) 'birth_date': birthDate,
      if (gender != null) 'gender': gender,
      if (phone != null) 'phone': phone,
      if (about != null) 'about': about,
      if (avatarBase64 != null) 'avatar_base64': avatarBase64,
      'clear_avatar': clearAvatar,
    };
    final json = await _put('/orgs/me/profile', body: body);
    return CloudUser.fromJson(json);
  }

  Future<List<ClientOrgSummary>> listClients({
    String? manufacturerOrganizationId,
  }) async {
    if (DemoSession.isActive) {
      return const [
        ClientOrgSummary(
          id: DemoFleetData.orgId,
          name: 'Завод «Севергидро» (демо)',
        ),
      ];
    }
    final query = <String, String>{};
    if (manufacturerOrganizationId != null &&
        manufacturerOrganizationId.isNotEmpty) {
      query['manufacturer_organization_id'] = manufacturerOrganizationId;
    }
    final json = await _get(
      '/orgs/clients',
      query: query.isEmpty ? null : query,
    );
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => ClientOrgSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ClientOrgSummary>> listManufacturers() async {
    if (DemoSession.isActive) {
      return const [
        ClientOrgSummary(id: 'demo-mfr', name: 'Производитель (демо)'),
      ];
    }
    final json = await _get('/orgs/manufacturers');
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => ClientOrgSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Админ платформы: создать производителя + его администратора.
  Future<Map<String, dynamic>> createManufacturer({
    required String name,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
  }) {
    return _post(
      '/orgs/manufacturers',
      body: {
        'name': name,
        'admin_name': adminName,
        'admin_email': adminEmail,
        'admin_password': adminPassword,
      },
    );
  }

  /// Производитель или админ платформы: создать завод + администратора.
  Future<Map<String, dynamic>> createClient({
    required String name,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    String? manufacturerOrganizationId,
  }) {
    final body = <String, dynamic>{
      'name': name,
      'admin_name': adminName,
      'admin_email': adminEmail,
      'admin_password': adminPassword,
    };
    if (manufacturerOrganizationId != null &&
        manufacturerOrganizationId.isNotEmpty) {
      body['manufacturer_organization_id'] = manufacturerOrganizationId;
    }
    return _post('/orgs/clients', body: body);
  }

  /// Админ завода или платформы: создать водителя.
  Future<CloudUser> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? assignedMachineId,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      'role': role,
    };
    if (assignedMachineId != null && assignedMachineId.isNotEmpty) {
      body['assigned_machine_id'] = assignedMachineId;
    }
    final json = await _post('/orgs/users', body: body);
    return CloudUser.fromJson(json);
  }

  Future<List<CloudUser>> listUsers() async {
    if (DemoSession.isActive) return [DemoFleetData.currentUser()];
    final json = await _get('/orgs/users');
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => CloudUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Админ организации: удалить пользователя (не себя).
  Future<void> deleteUser(String userId) => _delete('/orgs/users/$userId');

  /// Админ платформы: каскадное удаление организации.
  Future<Map<String, dynamic>> deleteOrganization(String orgId) async {
    await _delete('/orgs/$orgId');
    return {'deleted': true, 'id': orgId};
  }

  /// Админ завода: сменить машину водителя.
  Future<CloudUser> assignDriverMachine({
    required String userId,
    required String machineId,
  }) async {
    final json = await _post(
      '/orgs/users/$userId/assign-machine',
      body: {'assigned_machine_id': machineId},
    );
    return CloudUser.fromJson(json);
  }

  /// Производитель: передать / перепродать завод-клиенту.
  Future<void> transferMachine({
    required String machineId,
    required String clientOrganizationId,
  }) async {
    await _post(
      '/machines/id/$machineId/transfer',
      body: {'client_organization_id': clientOrganizationId},
    );
  }

  /// Админ платформы: закрепить за производителем.
  Future<void> assignManufacturer({
    required String machineId,
    required String manufacturerOrganizationId,
  }) async {
    await _post(
      '/machines/id/$machineId/assign-manufacturer',
      body: {'manufacturer_organization_id': manufacturerOrganizationId},
    );
  }
}
