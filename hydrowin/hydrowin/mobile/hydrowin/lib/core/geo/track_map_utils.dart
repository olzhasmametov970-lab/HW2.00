import 'dart:math' as math;

import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:latlong2/latlong.dart';

/// «Null Island» и пустой GPS до фикса.
bool isPlausibleGpsCoord(double lat, double lon) {
  if (lat.abs() >= 90 || lon.abs() > 180) return false;
  if (lat.abs() < 0.05 && lon.abs() < 0.05) return false;
  return true;
}

double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

/// Отфильтровать мусорные точки трека.
List<MachineTrackPoint> sanitizeTrackPoints(List<MachineTrackPoint> track) {
  final out = <MachineTrackPoint>[];
  MachineTrackPoint? prev;
  for (final p in track) {
    if (!isPlausibleGpsCoord(p.lat, p.lon)) continue;
    if (prev != null &&
        _haversineM(p.lat, p.lon, prev.lat, prev.lon) > 500000) {
      continue;
    }
    out.add(p);
    prev = p;
  }
  return out;
}

/// Разбить трек на сегменты без линий через полмира (скачок >5 км).
List<List<LatLng>> trackPolylineSegments(
  List<MachineTrackPoint> track, {
  double maxSegmentGapM = 5000,
}) {
  final clean = sanitizeTrackPoints(track);
  if (clean.isEmpty) return const [];

  final segments = <List<LatLng>>[];
  var current = <LatLng>[LatLng(clean.first.lat, clean.first.lon)];

  for (var i = 1; i < clean.length; i++) {
    final a = clean[i - 1];
    final b = clean[i];
    final gap = _haversineM(a.lat, a.lon, b.lat, b.lon);
    if (gap > maxSegmentGapM) {
      if (current.length >= 2) segments.add(current);
      current = <LatLng>[LatLng(b.lat, b.lon)];
    } else {
      current.add(LatLng(b.lat, b.lon));
    }
  }
  if (current.length >= 2) segments.add(current);
  return segments;
}
