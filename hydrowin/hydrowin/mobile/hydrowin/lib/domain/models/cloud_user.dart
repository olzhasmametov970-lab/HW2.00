import 'package:hydrowin/domain/models/cloud_organization.dart';

class CloudUser {
  const CloudUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.organizationId,
    this.organization,
    this.assignedMachineId,
    this.assignedMachineCode,
    this.assignedMachineName,
    this.firstName = '',
    this.lastName = '',
    this.birthDate,
    this.gender = '',
    this.phone = '',
    this.about = '',
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String organizationId;
  final CloudOrganization? organization;
  final String? assignedMachineId;
  final String? assignedMachineCode;
  final String? assignedMachineName;
  final String firstName;
  final String lastName;
  final String? birthDate;
  final String gender;
  final String phone;
  final String about;
  final String? avatarUrl;

  String? get machineLabel {
    final name = assignedMachineName?.trim();
    final code = assignedMachineCode?.trim();
    if (name != null && name.isNotEmpty && code != null && code.isNotEmpty) {
      return '$name ($code)';
    }
    if (name != null && name.isNotEmpty) return name;
    if (code != null && code.isNotEmpty) return code;
    return null;
  }

  factory CloudUser.fromJson(Map<String, dynamic> json) {
    return CloudUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      organizationId: json['organization_id'] as String,
      organization: json['organization'] != null
          ? CloudOrganization.fromJson(
              json['organization'] as Map<String, dynamic>,
            )
          : null,
      assignedMachineId: json['assigned_machine_id'] as String?,
      assignedMachineCode: json['assigned_machine_code'] as String?,
      assignedMachineName: json['assigned_machine_name'] as String?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      birthDate: json['birth_date'] as String?,
      gender: json['gender'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      about: json['about'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
