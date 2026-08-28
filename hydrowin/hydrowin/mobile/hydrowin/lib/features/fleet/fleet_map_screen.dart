import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/core/constants/map_tile_config.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/fleet/widgets/machine_status_chip.dart';
import 'package:latlong2/latlong.dart';

/// Карта парка: машины с GPS-точкой и список без координат (задать вручную).
class FleetMapScreen extends StatefulWidget {
  const FleetMapScreen({super.key});

  @override
  State<FleetMapScreen> createState() => _FleetMapScreenState();
}

class _FleetMapScreenState extends State<FleetMapScreen> {
  static const LatLng _defaultCenter = LatLng(56.83892, 60.60570);

  final MapController _map = MapController();
  bool _loading = true;
  String? _error;
  List<MachineSummary> _items = const [];
  MachineSummary? _selected;

  List<MachineSummary> get _withGps =>
      _items.where((m) => m.gps != null).toList(growable: false);

  List<MachineSummary> get _withoutGps =>
      _items.where((m) => m.gps == null).toList(growable: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await CloudScope.of(context).machines.listMachines();
      if (!mounted) return;
      setState(() {
        _items = data.items;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SessionExpiredException
            ? 'Сессия истекла — войдите снова'
            : e.toString();
        _loading = false;
      });
    }
  }

  void _fitMap() {
    final pts = _withGps
        .map((m) => LatLng(m.gps!.lat, m.gps!.lon))
        .toList(growable: false);
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 14);
      } else {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _editManual(MachineSummary machine) async {
    final current = machine.gps;
    final latController = TextEditingController(
      text: current?.lat.toStringAsFixed(5) ?? '56.83892',
    );
    final lngController = TextEditingController(
      text: current?.lon.toStringAsFixed(5) ?? '60.60570',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Координаты · ${machine.code}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Вручную, как на карточке машины. Если плата пришлёт GPS — точка обновится сама.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Широта'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lngController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Долгота'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;
    final lat = double.tryParse(latController.text.replaceAll(',', '.'));
    final lng = double.tryParse(lngController.text.replaceAll(',', '.'));
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректные координаты')),
      );
      return;
    }

    try {
      await CloudScope.of(context).machines.updateMachineDetails(
        machine.id,
        gps: MachineGps(lat: lat, lon: lng),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Координаты сохранены на сервере')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Найти устройства'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Повторить')),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(child: _buildMap(scheme)),
                _buildFooter(scheme),
              ],
            ),
    );
  }

  Widget _buildMap(ColorScheme scheme) {
    final withGps = _withGps;
    final center = withGps.isNotEmpty
        ? LatLng(withGps.first.gps!.lat, withGps.first.gps!.lon)
        : _defaultCenter;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: withGps.isEmpty ? 10 : 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: MapTileConfig.cartoVoyagerRasterUrl,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'ru.hydrowin.app',
              maxZoom: 19,
            ),
            MarkerLayer(
              markers: [
                for (final m in withGps)
                  Marker(
                    point: LatLng(m.gps!.lat, m.gps!.lon),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = m),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: machineStatusColor(m.status, scheme),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (withGps.isEmpty)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.28),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'На карте пока нет точек.\n'
                    'Дождитесь GPS с платы или задайте координаты вручную.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, height: 1.35),
                  ),
                ),
              ),
            ),
          ),
        if (_selected != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: ListTile(
                leading: Icon(
                  Icons.precision_manufacturing,
                  color: machineStatusColor(_selected!.status, scheme),
                ),
                title: Text(_selected!.code),
                subtitle: Text(
                  '${_selected!.name}\n'
                  '${_selected!.gps!.lat.toStringAsFixed(5)}, '
                  '${_selected!.gps!.lon.toStringAsFixed(5)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selected = null),
                ),
                onTap: () => context.push('/cloud/machine/${_selected!.id}'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    final missing = _withoutGps;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  'С GPS: ${_withGps.length}  ·  без точки: ${missing.length}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (missing.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('Все машины с координатами — нажмите метку на карте.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: missing.length,
                    itemBuilder: (ctx, i) {
                      final m = missing[i];
                      return ListTile(
                        dense: true,
                        title: Text(m.code),
                        subtitle: Text(m.name),
                        trailing: m.canConfigure
                            ? TextButton(
                                onPressed: () => _editManual(m),
                                child: const Text('Вручную'),
                              )
                            : const Text('нет точки'),
                        onTap: () => context.push('/cloud/machine/${m.id}'),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
