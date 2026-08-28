class CloudOrganization {
  const CloudOrganization({
    required this.id,
    required this.name,
    required this.orgType,
    this.manufacturerId,
  });

  final String id;
  final String name;
  final String orgType;
  final String? manufacturerId;

  bool get isPlatform => orgType == 'platform';
  bool get isManufacturer => orgType == 'manufacturer';
  bool get isClient => orgType == 'client';

  factory CloudOrganization.fromJson(Map<String, dynamic> json) {
    return CloudOrganization(
      id: json['id'] as String,
      name: json['name'] as String,
      orgType: json['org_type'] as String? ?? 'client',
      manufacturerId: json['manufacturer_id'] as String?,
    );
  }
}

class OrgMeResponse {
  const OrgMeResponse({
    required this.organization,
    required this.isManufacturer,
    this.isPlatform = false,
    this.isClient = false,
  });

  final CloudOrganization organization;
  final bool isManufacturer;
  final bool isPlatform;
  final bool isClient;

  factory OrgMeResponse.fromJson(Map<String, dynamic> json) {
    final org = CloudOrganization.fromJson(
      json['organization'] as Map<String, dynamic>,
    );
    return OrgMeResponse(
      organization: org,
      isManufacturer: json['is_manufacturer'] as bool? ?? org.isManufacturer,
      isPlatform: json['is_platform'] as bool? ?? org.isPlatform,
      isClient: json['is_client'] as bool? ?? org.isClient,
    );
  }
}

class ClientOrgSummary {
  const ClientOrgSummary({required this.id, required this.name});

  final String id;
  final String name;

  factory ClientOrgSummary.fromJson(Map<String, dynamic> json) {
    return ClientOrgSummary(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
