import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';
import 'package:hydrowin/domain/models/cloud_user.dart';
import 'package:hydrowin/domain/user_roles.dart';

/// Админ платформы / производителя / завода: пользователи с группировкой по заводам.
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _FactoryGroup {
  const _FactoryGroup({
    required this.id,
    required this.name,
    required this.users,
  });

  final String id;
  final String name;
  final List<CloudUser> users;
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  List<CloudUser> _users = const [];
  List<ClientOrgSummary> _factories = const [];
  String? _myEmail;
  String? _myOrgId;
  bool _isPlatform = false;
  bool _isManufacturer = false;
  bool _loading = true;
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
      if (!admin ||
          (!me.isPlatform && !me.isClient && !me.isManufacturer)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Доступно администратору завода, производителя или платформы',
            ),
          ),
        );
        context.pop();
        return;
      }
      final email = await scope.tokens.getUserEmail();
      setState(() {
        _allowed = true;
        _myEmail = email;
        _myOrgId = me.organization.id;
        _isPlatform = me.isPlatform;
        _isManufacturer = me.isManufacturer;
      });
      await _load();
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scope = CloudScope.of(context);
      final usersFuture = scope.organizations.listUsers();
      final factoriesFuture = (_isPlatform || _isManufacturer)
          ? scope.organizations.listClients()
          : Future.value(const <ClientOrgSummary>[]);
      final users = await usersFuture;
      final factories = await factoriesFuture;
      if (!mounted) return;
      setState(() {
        _users = users;
        _factories = factories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CloudScope.of(context).auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  List<_FactoryGroup> get _factoryGroups {
    final byOrg = <String, List<CloudUser>>{};
    for (final u in _users) {
      final org = u.organization;
      if (org != null && org.isClient) {
        byOrg.putIfAbsent(u.organizationId, () => []).add(u);
      } else if (org == null &&
          _factories.any((f) => f.id == u.organizationId)) {
        byOrg.putIfAbsent(u.organizationId, () => []).add(u);
      }
    }

    final groups = <_FactoryGroup>[];
    final seen = <String>{};

    for (final f in _factories) {
      seen.add(f.id);
      final list = byOrg[f.id] ?? const <CloudUser>[];
      groups.add(_FactoryGroup(id: f.id, name: f.name, users: list));
    }

    for (final entry in byOrg.entries) {
      if (seen.contains(entry.key)) continue;
      final name = entry.value.first.organization?.name ?? 'Завод';
      groups.add(
        _FactoryGroup(id: entry.key, name: name, users: entry.value),
      );
    }

    groups.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return groups;
  }

  List<CloudUser> get _platformUsers {
    if (!_isPlatform || _myOrgId == null) return const [];
    return _users
        .where(
          (u) =>
              u.organizationId == _myOrgId ||
              u.organization?.isPlatform == true,
        )
        .toList();
  }

  Future<void> _confirmDelete(CloudUser user) async {
    final isSelf =
        _myEmail != null &&
        user.email.toLowerCase() == _myEmail!.toLowerCase();
    if (isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя удалить свою учётную запись')),
      );
      return;
    }

    final roleLabel = UserRoles.label(user.role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пользователя?'),
        content: Text(
          '$roleLabel «${user.name}» (${user.email}) будет удалён.\n'
          'Войти под этой учёткой больше нельзя.',
        ),
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
      await CloudScope.of(context).organizations.deleteUser(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} удалён')),
      );
      await _load();
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

    final title = _isPlatform || _isManufacturer
        ? 'Заводы и водители'
        : 'Пользователи завода';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Создать водителя',
            onPressed: () async {
              await context.push('/admin/driver');
              if (mounted) await _load();
            },
          ),
        ],
      ),
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
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final platformUsers = _isPlatform ? _platformUsers : const <CloudUser>[];
    final factories = (_isPlatform || _isManufacturer)
        ? _factoryGroups
        : [
            _FactoryGroup(
              id: _myOrgId ?? '',
              name: 'Ваш завод',
              users: _users,
            ),
          ];

    if (platformUsers.isEmpty && factories.every((f) => f.users.isEmpty) && factories.isEmpty) {
      return const Center(child: Text('Пользователей пока нет'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (platformUsers.isNotEmpty) ...[
            _sectionHeader(
              context,
              icon: Icons.admin_panel_settings_outlined,
              title: 'Платформа',
            ),
            ...platformUsers.map(_userTile),
            const SizedBox(height: 16),
          ],
          if (_isPlatform || _isManufacturer)
            _sectionHeader(
              context,
              icon: Icons.factory_outlined,
              title: 'Заводы',
              subtitle: factories.isEmpty
                  ? 'Заводов пока нет'
                  : '${factories.length}',
            ),
          if (factories.isEmpty && (_isPlatform || _isManufacturer))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Создайте завод — водители появятся здесь'),
            ),
          for (final factory in factories) ...[
            _factoryCard(factory),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _factoryCard(_FactoryGroup factory) {
    final theme = Theme.of(context);
    final admins = factory.users
        .where((u) => !UserRoles.isDriver(u.role))
        .toList();
    final drivers = factory.users
        .where((u) => UserRoles.isDriver(u.role))
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(
          Icons.factory_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          factory.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _factorySubtitle(admins.length, drivers.length),
        ),
        children: [
          if (admins.isEmpty && drivers.isEmpty)
            const ListTile(
              dense: true,
              title: Text('Нет пользователей'),
              subtitle: Text('Добавьте админа или водителя завода'),
            ),
          if (admins.isNotEmpty) ...[
            _groupLabel('Администраторы'),
            ...admins.map(_userTile),
          ],
          if (drivers.isNotEmpty) ...[
            _groupLabel('Водители'),
            ...drivers.map(_userTile),
          ] else if (admins.isNotEmpty)
            const ListTile(
              dense: true,
              leading: Icon(Icons.local_shipping_outlined),
              title: Text('Водителей пока нет'),
            ),
        ],
      ),
    );
  }

  String _factorySubtitle(int admins, int drivers) {
    final parts = <String>[];
    if (admins > 0) parts.add('$admins адм.');
    if (drivers > 0) {
      parts.add('$drivers вод.');
    } else {
      parts.add('водителей нет');
    }
    return parts.join(' · ');
  }

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  Widget _userTile(CloudUser user) {
    final isSelf =
        _myEmail != null &&
        user.email.toLowerCase() == _myEmail!.toLowerCase();
    final isDriver = UserRoles.isDriver(user.role);
    final machine = user.machineLabel;

    final subtitleParts = <String>[
      UserRoles.label(user.role),
      user.email,
    ];
    if (isDriver) {
      subtitleParts.add(
        machine != null ? 'машина: $machine' : 'машина не назначена',
      );
    }

    return ListTile(
      leading: Icon(
        isDriver
            ? Icons.local_shipping_outlined
            : Icons.admin_panel_settings_outlined,
      ),
      title: Text(user.name),
      subtitle: Text(subtitleParts.join(' · ')),
      isThreeLine: isDriver,
      trailing: isSelf
          ? const Text('Вы', style: TextStyle(fontWeight: FontWeight.w600))
          : IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: 'Удалить',
              onPressed: () => _confirmDelete(user),
            ),
    );
  }
}
