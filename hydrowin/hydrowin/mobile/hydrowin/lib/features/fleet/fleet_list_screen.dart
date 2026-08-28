import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/fleet/widgets/machine_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class FleetListScreen extends StatefulWidget {
  const FleetListScreen({super.key});

  @override
  State<FleetListScreen> createState() => _FleetListScreenState();
}

class _FleetListScreenState extends State<FleetListScreen> {
  final _search = TextEditingController();
  String? _statusFilter;
  bool _loading = true;
  MachineListResponse? _data;
  String? _error;
  bool _isAdmin = false;
  CloudOrganization? _org;
  bool _isManufacturer = false;
  bool _isPlatform = false;
  Timer? _liveTimer;
  int _liveRefreshGen = 0;
  TelemetrySession? _telemetry;
  DateTime? _liveUpdatedAt;

  bool get _isPlatformAdmin => _isAdmin && _isPlatform;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _telemetry = AppScope.of(context);
      _telemetry!.addListener(_onPollIntervalChanged);
      _restartLiveTimer();
      final scope = CloudScope.of(context);
      unawaited(_loadProfile(scope));
      await _load();
    });
  }

  void _onPollIntervalChanged() => _restartLiveTimer();

  void _restartLiveTimer() {
    _liveTimer?.cancel();
    final seconds = (_telemetry?.pollSeconds ?? AppConstants.defaultPollSeconds)
        .clamp(AppConstants.minPollSeconds, AppConstants.maxPollSeconds);
    unawaited(_refreshFleetLive());
    _liveTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => unawaited(_refreshFleetLive()),
    );
  }

  FleetTotals _totalsFrom(List<MachineSummary> items) {
    return FleetTotals(
      total: items.length,
      ok: items.where((m) => m.status == MachineStatus.ok).length,
      warning: items.where((m) => m.status == MachineStatus.warning).length,
      critical: items.where((m) => m.status == MachineStatus.critical).length,
      offline: items.where((m) => m.status == MachineStatus.offline).length,
    );
  }

  Future<void> _refreshFleetLive() async {
    if (!mounted || _data == null || _loading) return;
    final gen = ++_liveRefreshGen;
    try {
      final live = await CloudScope.of(context).machines.getFleetLive();
      if (!mounted || gen != _liveRefreshGen) return;
      final byId = {for (final m in live.machines) m.machineId: m};
      final updated = _data!.items.map((machine) {
        final snap = byId[machine.id];
        if (snap == null) return machine;
        return machine.copyWith(
          status: snap.status,
          lastSeenAt: snap.lastSeenAt ?? machine.lastSeenAt,
        );
      }).toList();
      setState(() {
        _data = MachineListResponse(
          items: updated,
          totals: _totalsFrom(updated),
        );
        _liveUpdatedAt = DateTime.now();
      });
    } catch (_) {
      // Тихо — оставляем последние статусы, следующий тик повторит.
    }
  }

  Future<void> _exitToLogin() async {
    _liveTimer?.cancel();
    try {
      await AppScope.of(context).disconnect();
    } catch (_) {}
    try {
      await CloudScope.maybeOf(context)?.auth.logout();
    } catch (_) {}
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _loadProfile(CloudScope scope) async {
    final admin = await scope.auth.isAdmin();
    try {
      final me = await scope.organizations.fetchMe();
      if (mounted) {
        setState(() {
          _isAdmin = admin;
          _org = me.organization;
          _isManufacturer = me.isManufacturer;
          _isPlatform = me.isPlatform;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isAdmin = admin);
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _telemetry?.removeListener(_onPollIntervalChanged);
    _search.dispose();
    super.dispose();
  }

  Future<bool> _confirmHideMachine(MachineSummary machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать из парка?'),
        content: Text(
          '${machine.code} · ${machine.name} исчезнет из списка в этом приложении.\n'
          'На сервере машина и история останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _performHideMachine(MachineSummary machine) async {
    final scope = CloudScope.of(context);
    final remaining = (_data?.items ?? [])
        .where((m) => m.id != machine.id)
        .toList();
    setState(() {
      _data = MachineListResponse(
        items: remaining,
        totals: FleetTotals(
          total: remaining.length,
          ok: remaining.where((m) => m.status == MachineStatus.ok).length,
          warning: remaining
              .where((m) => m.status == MachineStatus.warning)
              .length,
          critical: remaining
              .where((m) => m.status == MachineStatus.critical)
              .length,
          offline: remaining
              .where((m) => m.status == MachineStatus.offline)
              .length,
        ),
      );
    });

    await scope.machines.hideMachineFromFleet(machine);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        dismissDirection: DismissDirection.down,
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => messenger.hideCurrentSnackBar(),
          child: Text(
            '${machine.code} убрана из списка (история на сервере сохранена)\n'
            'Нажмите, чтобы закрыть',
          ),
        ),
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () async {
            await scope.machines.unhideMachineFromFleet(machine.id);
            if (mounted) await _load(silent: true);
          },
        ),
      ),
    );
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    final scope = CloudScope.of(context);

    try {
      final data = await scope.machines.listMachines(
        status: _statusFilter,
        query: _search.text,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      unawaited(_refreshFleetLive());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SessionExpiredException
            ? 'Сессия истекла — войдите снова'
            : e is TimeoutException
            ? 'Сервер не ответил (${scope.api.baseUrl}). Проверьте интернет.'
            : e.toString();
        _loading = false;
      });
      if (e is SessionExpiredException && mounted) {
        context.go(AppConstants.isLite ? '/lite' : '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _data?.totals;

    return Scaffold(
      appBar: AppBar(
        leading: AppConstants.isLite
            ? BackButton(onPressed: () => context.go('/lite'))
            : BackButton(onPressed: _exitToLogin),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Парк машин'),
            if (_org != null)
              Text(
                _isManufacturer ? '${_org!.name} · производитель' : _org!.name,
                style: Theme.of(context).textTheme.labelMedium,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Найти устройства',
            onPressed: () => context.push('/fleet/map'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Уведомления',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Мониторинг по интернету (сервер)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_isPlatformAdmin && _liveUpdatedAt != null)
                    Text(
                      'Опрос парка: каждые '
                      '${_telemetry?.pollSeconds ?? AppConstants.defaultPollSeconds} с '
                      '(обновлено ${DateFormat('HH:mm:ss').format(_liveUpdatedAt!)})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          if (totals != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  _TotalChip(
                    label: 'Всего',
                    count: totals.total,
                    selected: _statusFilter == null,
                    onTap: () {
                      setState(() => _statusFilter = null);
                      _load();
                    },
                  ),
                  _TotalChip(
                    label: 'OK',
                    count: totals.ok,
                    color: Colors.green,
                    selected: _statusFilter == 'ok',
                    onTap: () {
                      setState(() => _statusFilter = 'ok');
                      _load();
                    },
                  ),
                  _TotalChip(
                    label: 'Внимание',
                    count: totals.warning,
                    color: Colors.orange,
                    selected: _statusFilter == 'warning',
                    onTap: () {
                      setState(() => _statusFilter = 'warning');
                      _load();
                    },
                  ),
                  _TotalChip(
                    label: 'Критично',
                    count: totals.critical,
                    color: Theme.of(context).colorScheme.error,
                    selected: _statusFilter == 'critical',
                    onTap: () {
                      setState(() => _statusFilter = 'critical');
                      _load();
                    },
                  ),
                  _TotalChip(
                    label: 'Оффлайн',
                    count: totals.offline,
                    selected: _statusFilter == 'offline',
                    onTap: () {
                      setState(() => _statusFilter = 'offline');
                      _load();
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/fleet/map'),
                icon: const Icon(Icons.location_searching),
                label: const Text('Найти устройства по GPS или вручную'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Поиск по номеру, названию, IP',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Загрузка парка…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final items = _data?.items ?? [];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('В парке пока нет машин', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                _isPlatformAdmin
                    ? 'Зарегистрируйте плату после прошивки — '
                          'машина появится сразу (офлайн до первой телеметрии).'
                    : _isManufacturer
                    ? 'Создайте завод или дождитесь передачи машин с платформы.'
                    : 'Обратитесь к администратору организации.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_isPlatformAdmin) ...[
                FilledButton.icon(
                  onPressed: () => context.push('/admin/register-board'),
                  icon: const Icon(Icons.developer_board),
                  label: const Text('Зарегистрировать плату'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.push('/admin/factory'),
                  child: const Text('Создать завод'),
                ),
              ] else if (_isManufacturer && _isAdmin) ...[
                FilledButton(
                  onPressed: () => context.push('/admin/factory'),
                  child: const Text('Создать завод'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final machine = items[index];
          final tile = MachineListTile(
            machine: machine,
            onTap: () {
              // Предпочитаем UUID — устойчиво после смены локации
              context.push('/cloud/machine/${machine.id}');
            },
          );

          if (!_isAdmin || machine.isReadOnlyForCurrentUser) return tile;

          return Dismissible(
            key: ValueKey(machine.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.visibility_off,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            confirmDismiss: (_) => _confirmHideMachine(machine),
            onDismissed: (_) => _performHideMachine(machine),
            child: tile,
          );
        },
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: (color ?? Theme.of(context).colorScheme.primary)
          .withValues(alpha: 0.2),
      checkmarkColor: color,
    );
  }
}
