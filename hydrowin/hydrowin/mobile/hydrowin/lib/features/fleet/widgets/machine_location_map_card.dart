import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hydrowin/core/constants/map_tile_config.dart';
import 'package:hydrowin/core/geo/track_map_utils.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:latlong2/latlong.dart';

/// Карта с маркером GPS (тайлы CartoCDN / данные OSM).
/// Не используем tile.openstreetmap.org — на web их режут (403 Tile Usage Policy).
/// Загружается отложенно и без жестов — иначе ListView на Windows сильно лагает.
/// Отдельная кнопка раскрывает карту на весь экран (мобильная и Windows).
class MachineLocationMapCard extends StatefulWidget {
  const MachineLocationMapCard({
    required this.gps,
    required this.track,
    required this.geofence,
    required this.machineCode,
    required this.canEdit,
    required this.onEdit,
    this.onOpenFleetMap,
    super.key,
  });

  final MachineGps? gps;
  final List<MachineTrackPoint> track;
  final MachineGeofence? geofence;
  final String machineCode;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onOpenFleetMap;

  @override
  State<MachineLocationMapCard> createState() => _MachineLocationMapCardState();
}

class _MachineLocationMapCardState extends State<MachineLocationMapCard> {
  static const LatLng _defaultCenter = LatLng(56.83892, 60.60570);

  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    // Даём экрану отрисоваться, потом подключаем тяжёлые тайлы OSM.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _mapReady = true);
      });
    });
  }

  LatLng get _point {
    final gps = widget.gps;
    if (gps != null && isPlausibleGpsCoord(gps.lat, gps.lon)) {
      return LatLng(gps.lat, gps.lon);
    }
    return _defaultCenter;
  }

  bool get _hasGps {
    final gps = widget.gps;
    return gps != null && isPlausibleGpsCoord(gps.lat, gps.lon);
  }

  List<List<LatLng>> get _trackSegments =>
      trackPolylineSegments(widget.track);

  void _onFindDevices() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.gps_fixed),
                title: const Text('По GPS с платы'),
                subtitle: Text(
                  _hasGps
                      ? 'Открыть карту парка с этой точкой'
                      : 'Фикса ещё нет — антенна GNSS, открытое небо, 1–5 мин',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_hasGps) {
                    widget.onOpenFleetMap?.call();
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Плата ещё без GPS. Дождитесь фикса или задайте точку вручную.',
                      ),
                    ),
                  );
                },
              ),
              if (widget.canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_location_alt),
                  title: const Text('Задать вручную'),
                  subtitle: const Text('Широта и долгота, как сейчас'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onEdit();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openExpandedMap() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть карту',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondary) {
        return _ExpandedMachineMapPage(
          gps: widget.gps,
          track: widget.track,
          geofence: widget.geofence,
          machineCode: widget.machineCode,
          center: _point,
          hasGps: _hasGps,
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gps = widget.gps;
    final geofence = widget.geofence;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                if (!_mapReady)
                  ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  RepaintBoundary(
                    child: _MachineMapView(
                      mapKey: ValueKey(
                        _hasGps
                            ? '${gps!.lat.toStringAsFixed(5)},${gps.lon.toStringAsFixed(5)}'
                            : 'no-gps',
                      ),
                      center: _point,
                      hasGps: _hasGps,
                      geofence: geofence,
                      trackSegments: _trackSegments,
                      interact: false,
                      backgroundColor: scheme.surfaceContainerHighest,
                      primary: scheme.primary,
                      tertiary: scheme.tertiary,
                    ),
                  ),
                if (!_hasGps && _mapReady)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Координаты ещё не заданы.\n'
                            'Точка с платы появится после GPS-фикса.\n'
                            'Или укажите широту и долготу вручную.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, height: 1.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.machineCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasGps
                            ? 'Широта: ${gps!.lat.toStringAsFixed(5)}'
                            : 'Широта: —',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                      Text(
                        _hasGps
                            ? 'Долгота: ${gps!.lon.toStringAsFixed(5)}'
                            : 'Долгота: —',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        geofence == null
                            ? 'Геозона: не задана'
                            : geofence.inside == false
                                ? 'Геозона: вне региона'
                                : 'Геозона: внутри региона',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: geofence?.inside == false
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (widget.canEdit)
                  TextButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_location_alt, size: 16),
                    label: Text(_hasGps ? 'Изменить' : 'Задать'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _onFindDevices,
                icon: const Icon(Icons.location_searching),
                label: const Text('Найти устройства по GPS или вручную'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: OutlinedButton.icon(
              onPressed: _openExpandedMap,
              icon: const Icon(Icons.open_in_full, size: 18),
              label: const Text('Раскрыть карту'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MachineMapView extends StatelessWidget {
  const _MachineMapView({
    required this.mapKey,
    required this.center,
    required this.hasGps,
    required this.geofence,
    required this.trackSegments,
    required this.interact,
    required this.backgroundColor,
    required this.primary,
    required this.tertiary,
    this.initialZoom,
  });

  final Key mapKey;
  final LatLng center;
  final bool hasGps;
  final MachineGeofence? geofence;
  final List<List<LatLng>> trackSegments;
  final bool interact;
  final Color backgroundColor;
  final Color primary;
  final Color tertiary;
  final double? initialZoom;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      key: mapKey,
      options: MapOptions(
        initialCenter: center,
        initialZoom: initialZoom ?? (hasGps ? 13 : 10),
        backgroundColor: backgroundColor,
        interactionOptions: InteractionOptions(
          flags: interact
              ? InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          // Carto raster — ключ CARTO_BASEMAP_KEY при сборке (release-config.ps1).
          urlTemplate: MapTileConfig.cartoVoyagerRasterUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'ru.hydrowin.app',
          maxZoom: 19,
          keepBuffer: interact ? 2 : 1,
          panBuffer: interact ? 1 : 0,
        ),
        if (geofence != null && geofence!.enabled)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(geofence!.centerLat, geofence!.centerLon),
                radius: geofence!.radiusM,
                useRadiusInMeter: true,
                color: primary.withValues(alpha: 0.14),
                borderStrokeWidth: 2,
                borderColor: primary,
              ),
            ],
          ),
        if (trackSegments.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final seg in trackSegments)
                Polyline(
                  points: seg,
                  strokeWidth: 3,
                  color: tertiary,
                ),
            ],
          ),
        if (hasGps)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: Icon(
                  Icons.location_on,
                  color: primary,
                  size: 36,
                ),
              ),
            ],
          ),
        // Требование лицензии данных OSM / Carto.
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap'),
            TextSourceAttribution('CARTO'),
          ],
          alignment: AttributionAlignment.bottomRight,
          showFlutterMapAttribution: false,
        ),
      ],
    );
  }
}

class _ExpandedMachineMapPage extends StatelessWidget {
  const _ExpandedMachineMapPage({
    required this.gps,
    required this.track,
    required this.geofence,
    required this.machineCode,
    required this.center,
    required this.hasGps,
  });

  final MachineGps? gps;
  final List<MachineTrackPoint> track;
  final MachineGeofence? geofence;
  final String machineCode;
  final LatLng center;
  final bool hasGps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trackSegments = trackPolylineSegments(track);
    final media = MediaQuery.sizeOf(context);
    final wide = media.width >= 900;
    final gpsPoint = hasGps ? gps : null;
    final coordLabel = gpsPoint == null
        ? null
        : '${gpsPoint.lat.toStringAsFixed(5)},${gpsPoint.lon.toStringAsFixed(5)}';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? media.width * 0.92 : media.width,
            maxHeight: wide ? media.height * 0.92 : media.height,
          ),
          child: Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(wide ? 16 : 0),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Карта · $machineCode',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _MachineMapView(
                        mapKey: ValueKey(
                          coordLabel == null ? 'full-no-gps' : 'full-$coordLabel',
                        ),
                        center: center,
                        hasGps: hasGps,
                        geofence: geofence,
                        trackSegments: trackSegments,
                        interact: true,
                        backgroundColor: scheme.surfaceContainerHighest,
                        primary: scheme.primary,
                        tertiary: scheme.tertiary,
                        initialZoom: hasGps ? 14 : 10,
                      ),
                      if (!hasGps)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Координаты ещё не заданы',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            coordLabel ?? machineCode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
