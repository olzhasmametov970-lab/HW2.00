import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/fleet/widgets/machine_status_chip.dart';
import 'package:go_router/go_router.dart';

/// Выбор машины для настройки порогов датчиков (облако).
class CloudThresholdsPickerScreen extends StatefulWidget {
  const CloudThresholdsPickerScreen({super.key});

  @override
  State<CloudThresholdsPickerScreen> createState() =>
      _CloudThresholdsPickerScreenState();
}

class _CloudThresholdsPickerScreenState
    extends State<CloudThresholdsPickerScreen> {
  final _search = TextEditingController();
  List<MachineSummary> _items = [];
  bool _loading = true;
  String? _error;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final admin = await CloudScope.of(context).auth.isAdmin();
    if (!mounted) return;
    setState(() => _isAdmin = admin);
    if (!admin) {
      setState(() {
        _loading = false;
        _error = 'Настройка датчиков доступна администраторам организации.';
      });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final res = await CloudScope.of(context).machines.listMachines(
            query: q.isEmpty ? null : q,
          );
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is SessionExpiredException) {
        context.go('/login');
        return;
      }
      setState(() {
        _error = CloudScope.of(context).auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка датчиков'),
      ),
      body: !_isAdmin && !_loading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Нет доступа',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Выберите машину, у которой нужно изменить пороги '
                    '(норма / критично).',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Поиск по коду или имени',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loading ? null : _load,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
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
                                    FilledButton(
                                      onPressed: _load,
                                      child: const Text('Повторить'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _items.isEmpty
                              ? const Center(child: Text('Машин не найдено'))
                              : ListView.separated(
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final m = _items[i];
                                    final canEdit = m.canConfigure;
                                    final statusColor =
                                        machineStatusColor(m.status, scheme);
                                    return ListTile(
                                      title: Text('${m.code} · ${m.name}'),
                                      subtitle: Text(
                                        [
                                          m.locationLabel,
                                          if (canEdit)
                                            'можно изменить'
                                          else
                                            'только просмотр',
                                        ].join(' · '),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Chip(
                                            label: Text(
                                              machineStatusLabel(m.status),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            side: BorderSide(
                                              color: statusColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            canEdit
                                                ? Icons.tune
                                                : Icons.visibility_outlined,
                                          ),
                                        ],
                                      ),
                                      onTap: () => context.push(
                                        '/sensors/thresholds/${m.id}',
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
    );
  }
}
