import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/fleet_registry_repository.dart';
import 'package:hydrowin/domain/models/fleet_machine_entry.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/core/api/api_config.dart';

class SingleMachineSetupScreen extends StatefulWidget {
  const SingleMachineSetupScreen({super.key});

  @override
  State<SingleMachineSetupScreen> createState() =>
      _SingleMachineSetupScreenState();
}

class _SingleMachineSetupScreenState extends State<SingleMachineSetupScreen> {
  final _number = TextEditingController(text: '001');
  final _name = TextEditingController(text: 'Моя машина');
  final _ip = TextEditingController();
  final _model = TextEditingController(text: 'Экскаватор');
  bool _loading = true;
  FleetRegistryRepository? _repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _repo = await FleetRegistryRepository.create();
    final prefs = await AppPreferences.create();
    final id = prefs.singleMachineId;
    if (id != null) {
      final entry = await _repo!.findById(id);
      if (entry != null) {
        _number.text = entry.number;
        _name.text = entry.name;
        _ip.text = entry.ipAddress;
        _model.text = entry.model ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _ip.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final number = _number.text.trim();
    final name = _name.text.trim();
    final ip = _ip.text.trim();

    if (number.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите номер и название машины')),
      );
      return;
    }

    // ВАЖНО: Проверяем, что IP-адрес заполнен, так как бэкенд ищет датчики по нему
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, введите IP-адрес блока')),
      );
      return;
    }

    // Внутренний ID = IP блока (ключ для /machines/{ip}/sensors).
    final entry = FleetMachineEntry(
      id: ip,
      number: number,
      name: name,
      ipAddress: ip,
      model: _model.text.trim().isEmpty ? null : _model.text.trim(),
    );

    // ОТПРАВЛЯЕМ ДАННЫЕ НА БЭКЕНД (СИНХРОНИЗАЦИЯ)
    try {
      final url = Uri.parse('${ApiConfig.defaultBaseUrl}/machines/$number');
      final request = await HttpClient().putUrl(url);
      request.headers.set('content-type', 'application/json');

      // Пакуем данные в JSON для эндпоинта FastAPI
      request.add(
        utf8.encode(
          jsonEncode({
            'code': number,
            'name': name,
            'model': entry.model ?? '',
            'location_label': ip, // Передаем IP в location_label
          }),
        ),
      );

      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('Ошибка на сервере. Код: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка отправки на сервер: $e');
    }

    // Сохраняем локально и переходим дальше
    final prefs = await AppPreferences.create();
    await _repo!.save([entry]);
    await prefs.setSingleMachineId(entry.id); // Сохраняем IP как рабочий ID

    if (!mounted) return;
    context.go('/sensors/setup?from=single');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка машины'),
        leading: BackButton(onPressed: () => context.go('/fleet')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Датчики на блоке передают данные на server по Wi‑Fi или GSM. '
            'Приложение получает их только через интернет.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _number,
            decoration: const InputDecoration(
              labelText: 'Номер машины',
              hintText: '001',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Модель (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ip,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'IP-адрес блока (Обязательно)',
              hintText: 'например 10.0.0.50',
              border: OutlineInputBorder(),
              helperText:
                  'Используется для запроса телеметрии датчиков с сервера',
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _save,
            child: const Text('ДАЛЕЕ — НАСТРОЙКА ДАТЧИКОВ'),
          ),
        ],
      ),
    );
  }
}
