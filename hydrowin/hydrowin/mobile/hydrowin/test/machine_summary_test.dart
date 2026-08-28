import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';

void main() {
  test('MachineSummary parses API JSON', () {
    final m = MachineSummary.fromJson({
      'id': 'uuid-1',
      'code': '#001',
      'name': 'Test',
      'model': 'CAT',
      'status': 'warning',
      'location_label': 'North',
      'operator_name': 'Ivan',
      'headline_alert': 'Alert',
      'engine_hours': 100.5,
      'last_seen_at': '2026-05-18T10:00:00Z',
    });

    expect(m.status, MachineStatus.warning);
    expect(m.headlineAlert, 'Alert');
    expect(m.engineHours, 100.5);
    expect(m.lastSeenAt, isNotNull);
  });
}
