import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/data/local/service_fault_journal.dart';
import 'package:intl/intl.dart';

/// Журнал аварий петли 4–20 мА: история + поиск по машине / каналу.
class ServiceFaultJournalScreen extends StatefulWidget {
  const ServiceFaultJournalScreen({super.key});

  @override
  State<ServiceFaultJournalScreen> createState() =>
      _ServiceFaultJournalScreenState();
}

class _ServiceFaultJournalScreenState extends State<ServiceFaultJournalScreen> {
  final _search = TextEditingController();
  List<ServiceFaultEntry> _items = const [];
  bool _loading = true;
  String _faultFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await AppScope.faultJournalOf(context).list(
      query: _search.text,
      loopFault: _faultFilter,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Map<String, List<ServiceFaultEntry>> _groupByDay(List<ServiceFaultEntry> items) {
    final fmt = DateFormat('dd.MM.yyyy');
    final map = <String, List<ServiceFaultEntry>>{};
    for (final e in items) {
      final key = fmt.format(e.recordedAt.toLocal());
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm:ss');
    final grouped = _groupByDay(_items);
    final days = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал петли 4–20 мА'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: 'К парку машин',
            icon: const Icon(Icons.precision_manufacturing_outlined),
            onPressed: () => context.go('/fleet'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Поиск: машина, канал, датчик…',
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
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final f in const [
                  ('all', 'Все'),
                  ('open', 'Обрыв'),
                  ('short', 'КЗ'),
                  ('none', 'Порог'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(f.$2),
                      selected: _faultFilter == f.$1,
                      onSelected: (_) {
                        setState(() => _faultFilter = f.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading
                    ? 'Загрузка…'
                    : 'История: ${_items.length} записей'
                        '${_search.text.trim().isEmpty ? '' : ' · фильтр «${_search.text.trim()}»'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _search.text.trim().isEmpty &&
                                        _faultFilter == 'all'
                                    ? 'Пока нет записей.\n'
                                        'Обрыв, КЗ и критичные пороги '
                                        'сохраняются сюда с током петли.'
                                    : 'Ничего не найдено.\n'
                                        'Измените поиск или фильтр.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => context.go('/fleet'),
                                icon: const Icon(Icons.search),
                                label: const Text('Искать машины в парке'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: days.length,
                          itemBuilder: (context, dayIndex) {
                            final day = days[dayIndex];
                            final dayItems = grouped[day]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    day,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                for (final e in dayItems) ...[
                                  Card(
                                    child: ListTile(
                                      title: Text(e.title),
                                      subtitle: Text(
                                        '${e.detail}\n'
                                        '${e.deviceLabel ?? 'Машина не указана'}'
                                        ' · CH${e.channelIndex}'
                                        '${e.currentMa != null ? ' · ${e.currentMa!.toStringAsFixed(1)} мА' : ''}\n'
                                        '${timeFmt.format(e.recordedAt.toLocal())}',
                                      ),
                                      isThreeLine: true,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
