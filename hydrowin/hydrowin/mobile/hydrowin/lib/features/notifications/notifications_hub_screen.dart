import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';
import 'package:hydrowin/data/remote/events_repository.dart';
import 'package:hydrowin/data/remote/notifications_repository.dart';
import 'package:intl/intl.dart';

/// Центр: оповещения (только аварии) + журнал (события + безопасность).
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key});

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _JournalRow {
  const _JournalRow({
    required this.id,
    required this.ts,
    required this.severity,
    required this.message,
    required this.badge,
    this.machineId,
    this.machineTitle,
    this.acknowledged = false,
    this.isAudit = false,
    this.event,
  });

  final String id;
  final DateTime ts;
  final String severity;
  final String message;
  final String badge;
  final String? machineId;
  final String? machineTitle;
  final bool acknowledged;
  final bool isAudit;
  final MachineEventItem? event;
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  List<MachineEventItem> _active = [];
  List<_JournalRow> _journal = [];
  bool _loading = true;
  String? _error;
  String? _ackingId;
  String _severityFilter = 'all'; // all | critical | warning | info

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = CloudScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final severity = _severityFilter == 'all' ? null : _severityFilter;
      final active = await scope.events.listEvents(
        acknowledged: false,
        severity: 'critical',
      );
      final events = await scope.events.listEvents(q: q, severity: severity);
      List<AuditLogItem> audit = const [];
      try {
        audit = await scope.notifications.listAudit(q: q.isEmpty ? null : q);
      } catch (_) {
        // журнал событий всё равно покажем
      }
      if (!mounted) return;

      final rows = <_JournalRow>[
        ...events.map(
          (e) => _JournalRow(
            id: 'e-${e.id}',
            ts: e.ts,
            severity: e.severity,
            message: e.message,
            badge: e.severity.toUpperCase(),
            machineId: e.machineId,
            machineTitle: [
              if (e.machineCode != null && e.machineCode!.isNotEmpty)
                e.machineCode,
              if (e.machineName != null && e.machineName!.isNotEmpty)
                e.machineName,
            ].join(' · '),
            acknowledged: e.acknowledged,
            event: e,
          ),
        ),
        if (_severityFilter == 'all' || _severityFilter == 'info')
          ...audit.map(
            (a) => _JournalRow(
              id: 'a-${a.id}',
              ts: a.ts,
              severity: a.severity,
              message: a.message,
              badge: _auditBadge(a.action),
              isAudit: true,
            ),
          ),
      ]..sort((a, b) => b.ts.compareTo(a.ts));

      setState(() {
        _active = active;
        _journal = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final auth = scope.auth;
      setState(() {
        _error = e is SessionExpiredException
            ? 'Сессия истекла — войдите снова'
            : auth.humanizeError(e);
        _loading = false;
      });
      if (e is SessionExpiredException) context.go('/login');
    }
  }

  String _auditBadge(String action) {
    if (action.startsWith('auth.')) return 'ВХОД';
    if (action.startsWith('settings.')) return 'НАСТРОЙКИ';
    if (action.startsWith('notify.')) return 'КАНАЛ';
    if (action.startsWith('event.')) return 'АВАРИЯ';
    return 'АУДИТ';
  }

  Future<void> _ack(MachineEventItem item) async {
    setState(() => _ackingId = item.id);
    try {
      final updated = await CloudScope.of(context).events.acknowledge(item.id);
      if (!mounted) return;
      setState(() {
        _active.removeWhere((e) => e.id == item.id);
        final idx = _journal.indexWhere((e) => e.event?.id == item.id);
        if (idx >= 0) {
          final old = _journal[idx];
          _journal[idx] = _JournalRow(
            id: old.id,
            ts: old.ts,
            severity: old.severity,
            message: old.message,
            badge: old.badge,
            machineId: old.machineId,
            machineTitle: old.machineTitle,
            acknowledged: true,
            event: updated,
          );
        }
        _ackingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ackingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              text: _active.isEmpty
                  ? 'Оповещения'
                  : 'Оповещения (${_active.length})',
            ),
            const Tab(text: 'Журнал'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Каналы оповещений',
            onPressed: () => context.push('/notifications/prefs'),
            icon: const Icon(Icons.tune),
          ),
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
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Text(
                            'Только реальные аварии. Мелкие скачки — в журнале.',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _EventList(
                            items: _active,
                            emptyLabel: 'Нет активных аварий',
                            ackingId: _ackingId,
                            onAcknowledge: _ack,
                            showAck: true,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: TextField(
                            controller: _search,
                            decoration: InputDecoration(
                              hintText: 'Поиск ошибок, входов, настроек…',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _search.clear();
                                        _load();
                                      },
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _load(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              for (final f in const [
                                ('all', 'Все'),
                                ('critical', 'Аварии'),
                                ('warning', 'Скачки'),
                                ('info', 'Безопасность'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text(f.$2),
                                    selected: _severityFilter == f.$1,
                                    onSelected: (_) {
                                      setState(() => _severityFilter = f.$1);
                                      _load();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _JournalList(
                            items: _journal,
                            emptyLabel: 'Журнал пуст',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({
    required this.items,
    required this.emptyLabel,
    required this.ackingId,
    required this.onAcknowledge,
    required this.showAck,
  });

  final List<MachineEventItem> items;
  final String emptyLabel;
  final String? ackingId;
  final Future<void> Function(MachineEventItem) onAcknowledge;
  final bool showAck;

  Color _sevColor(String severity) => switch (severity) {
        'critical' => HwColors.critical,
        'warning' => HwColors.warn,
        _ => HwColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final fmt = DateFormat('dd.MM.yyyy HH:mm:ss');
    return RefreshIndicator(
      onRefresh: () async {
        final state =
            context.findAncestorStateOfType<_NotificationsHubScreenState>();
        await state?._load();
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = items[i];
          final accent = _sevColor(e.severity);
          final title = [
            if (e.machineCode != null && e.machineCode!.isNotEmpty)
              e.machineCode,
            if (e.machineName != null && e.machineName!.isNotEmpty)
              e.machineName,
          ].join(' · ');
          return _AlertTile(
            accent: accent,
            title: title.isEmpty ? e.machineId : title,
            badge: e.severity.toUpperCase(),
            message: e.message,
            time: fmt.format(e.ts),
            acknowledged: e.acknowledged,
            showAck: showAck,
            acking: ackingId == e.id,
            onTap: e.machineId.isEmpty
                ? null
                : () => context.push('/cloud/machine/${e.machineId}'),
            onAck: () => onAcknowledge(e),
          );
        },
      ),
    );
  }
}

class _JournalList extends StatelessWidget {
  const _JournalList({required this.items, required this.emptyLabel});

  final List<_JournalRow> items;
  final String emptyLabel;

  Color _sevColor(String severity) => switch (severity) {
        'critical' => HwColors.critical,
        'warning' => HwColors.warn,
        _ => HwColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final fmt = DateFormat('dd.MM.yyyy HH:mm:ss');
    return RefreshIndicator(
      onRefresh: () async {
        final state =
            context.findAncestorStateOfType<_NotificationsHubScreenState>();
        await state?._load();
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = items[i];
          return _AlertTile(
            accent: _sevColor(e.severity),
            title: e.machineTitle?.isNotEmpty == true
                ? e.machineTitle!
                : (e.isAudit ? 'Безопасность' : 'Событие'),
            badge: e.badge,
            message: e.message,
            time: fmt.format(e.ts),
            acknowledged: e.acknowledged,
            showAck: false,
            acking: false,
            onTap: e.machineId == null || e.machineId!.isEmpty
                ? null
                : () => context.push('/cloud/machine/${e.machineId}'),
            onAck: () async {},
          );
        },
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.accent,
    required this.title,
    required this.badge,
    required this.message,
    required this.time,
    required this.acknowledged,
    required this.showAck,
    required this.acking,
    required this.onTap,
    required this.onAck,
  });

  final Color accent;
  final String title;
  final String badge;
  final String message;
  final String time;
  final bool acknowledged;
  final bool showAck;
  final bool acking;
  final VoidCallback? onTap;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.55),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              badge,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.9),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            if (acknowledged)
                              Text(
                                'Подтверждено',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            else if (showAck)
                              TextButton(
                                onPressed: acking ? null : onAck,
                                child: acking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Подтвердить'),
                              ),
                          ],
                        ),
                      ],
                    ),
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
