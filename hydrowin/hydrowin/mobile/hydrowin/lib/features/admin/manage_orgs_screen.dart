import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';

/// Админ платформы: список производителей / заводов и каскадное удаление.
class ManageOrgsScreen extends StatefulWidget {
  const ManageOrgsScreen({super.key});

  @override
  State<ManageOrgsScreen> createState() => _ManageOrgsScreenState();
}

class _ManageOrgsScreenState extends State<ManageOrgsScreen> {
  List<ClientOrgSummary> _makers = const [];
  ClientOrgSummary? _selectedMaker;
  List<ClientOrgSummary> _clients = const [];
  bool _loading = true;
  bool _loadingClients = false;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAndLoad());
  }

  Future<void> _guardAndLoad() async {
    final scope = CloudScope.of(context);
    try {
      final me = await scope.organizations.fetchMe();
      final admin = await scope.auth.isAdmin();
      if (!mounted) return;
      if (!admin || !me.isPlatform) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Доступно только администратору платформы'),
          ),
        );
        context.pop();
        return;
      }
      setState(() => _allowed = true);
      await _loadMakers();
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _loadMakers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final makers = await CloudScope.of(context).organizations
          .listManufacturers();
      if (!mounted) return;
      setState(() {
        _makers = makers;
        _loading = false;
      });
      if (_selectedMaker != null) {
        final still = makers.where((m) => m.id == _selectedMaker!.id).firstOrNull;
        if (still == null) {
          setState(() {
            _selectedMaker = null;
            _clients = const [];
          });
        } else {
          await _loadClients(still);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CloudScope.of(context).auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadClients(ClientOrgSummary maker) async {
    setState(() {
      _selectedMaker = maker;
      _loadingClients = true;
    });
    try {
      final clients = await CloudScope.of(context).organizations.listClients(
        manufacturerOrganizationId: maker.id,
      );
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _loadingClients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingClients = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  Future<void> _confirmDeleteOrg({
    required ClientOrgSummary org,
    required bool isManufacturer,
  }) async {
    final title = isManufacturer
        ? 'Удалить производителя?'
        : 'Удалить завод?';
    final body = isManufacturer
        ? '«${org.name}» будет удалён вместе со всеми заводами, '
              'пользователями и машинами (включая историю датчиков).\n'
              'Это необратимо.'
        : '«${org.name}» будет удалён вместе с пользователями и машинами '
              '(включая историю датчиков).\nЭто необратимо.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await CloudScope.of(context).organizations.deleteOrganization(org.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${org.name}» удалён')),
      );
      await _loadMakers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CloudScope.of(context).auth.humanizeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Организации')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
              FilledButton(
                onPressed: _loadMakers,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMakers,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Производители',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Удаление производителя каскадом убирает его заводы, '
            'пользователей и машины.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_makers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Производителей пока нет')),
            )
          else
            ..._makers.map((m) {
              final selected = _selectedMaker?.id == m.id;
              return Card(
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : null,
                child: ListTile(
                  title: Text(m.name),
                  subtitle: Text(selected ? 'Заводы ниже' : 'Нажмите, чтобы открыть заводы'),
                  onTap: () => _loadClients(m),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: 'Удалить производителя',
                    onPressed: () => _confirmDeleteOrg(
                      org: m,
                      isManufacturer: true,
                    ),
                  ),
                ),
              );
            }),
          if (_selectedMaker != null) ...[
            const SizedBox(height: 24),
            Text(
              'Заводы · ${_selectedMaker!.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_loadingClients)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_clients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Заводов у этого производителя нет'),
              )
            else
              ..._clients.map(
                (c) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.factory_outlined),
                    title: Text(c.name),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Удалить завод',
                      onPressed: () => _confirmDeleteOrg(
                        org: c,
                        isManufacturer: false,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
