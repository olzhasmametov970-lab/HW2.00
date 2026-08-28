import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrowin/data/notifications/alert_notification_service.dart';

/// Локальный toast в правой колонке (не OS).
class SideToastItem {
  SideToastItem({
    required this.id,
    required this.machineId,
    required this.code,
    required this.name,
    required this.statusName,
    required this.headline,
    required this.createdAt,
  });

  final String id;
  final String machineId;
  final String code;
  final String name;
  final String statusName;
  final String headline;
  final DateTime createdAt;

  bool get isCritical => statusName == 'critical';
}

/// Анти-спам + очередь side-toast при смене статуса парка.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({AlertNotificationService? alerts}) : _alerts = alerts;

  final AlertNotificationService? _alerts;

  static const _maxVisible = 4;
  static const _cooldown = Duration(seconds: 45);

  final List<SideToastItem> _toasts = [];
  final Map<String, String> _lastStatus = {};
  final Map<String, DateTime> _lastToastAt = {};
  final Map<String, String> _lastHeadline = {};

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Из «Каналы оповещений»: Push в приложении.
  bool _pushEnabled = true;

  List<SideToastItem> get toasts => List.unmodifiable(_toasts);
  bool get pushEnabled => _pushEnabled;

  void setPushEnabled(bool enabled) {
    if (_pushEnabled == enabled) return;
    _pushEnabled = enabled;
    if (!enabled) {
      if (_toasts.isNotEmpty) {
        _toasts.clear();
        notifyListeners();
      }
    }
  }

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state;
  }

  bool get _appObscured =>
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.inactive;

  int _rank(String status) => switch (status) {
        'critical' => 3,
        'warning' => 2,
        'ok' => 1,
        _ => 0,
      };

  /// Тост только при входе в critical (реальная авария).
  /// Warning пишется в журнал на сервере, без тревоги в UI.
  /// Учитывает тумблер «Push в приложении».
  void observeMachineStatus({
    required String machineId,
    required String code,
    required String name,
    required String statusName,
    String? headline,
  }) {
    final prev = _lastStatus[machineId];
    _lastStatus[machineId] = statusName;

    final isAlert = statusName == 'critical';
    if (!isAlert) {
      _dismissForMachine(machineId);
      return;
    }

    if (!_pushEnabled) {
      _dismissForMachine(machineId);
      return;
    }

    final text = (headline != null && headline.trim().isNotEmpty)
        ? headline.trim()
        : 'Критическое состояние';

    final alertKind = _alertKind(text, statusName);

    final unchanged = prev == statusName && _lastHeadline[machineId] == text;
    if (unchanged) return;

    final lastAt = _lastToastAt[machineId];
    final inCooldown =
        lastAt != null && DateTime.now().difference(lastAt) < _cooldown;
    final onlyHeadlineFlicker =
        prev == statusName && _lastHeadline[machineId] != text;
    if (inCooldown &&
        onlyHeadlineFlicker &&
        _rank(statusName) <= _rank(prev ?? '')) {
      _lastHeadline[machineId] = text;
      return;
    }

    _pushToast(
      machineId: machineId,
      code: code,
      name: name,
      statusName: statusName,
      headline: text,
      alertKind: alertKind,
    );
  }

  /// Заголовок OS/side toast для обрыва и КЗ из headline_alert облака.
  static String _alertKind(String headline, String statusName) {
    final h = headline.toLowerCase();
    if (h.contains('обрыв')) return 'Обрыв цепи';
    if (h.contains('коротк') || h.contains('кз')) return 'Короткое замыкание';
    return 'Критично';
  }

  void _pushToast({
    required String machineId,
    required String code,
    required String name,
    required String statusName,
    required String headline,
    required String alertKind,
  }) {
    _dismissForMachine(machineId, notify: false);
    final item = SideToastItem(
      id: '${machineId}_${DateTime.now().microsecondsSinceEpoch}',
      machineId: machineId,
      code: code,
      name: name,
      statusName: statusName,
      headline: headline,
      createdAt: DateTime.now(),
    );
    _toasts.insert(0, item);
    while (_toasts.length > _maxVisible) {
      _toasts.removeLast();
    }
    _lastToastAt[machineId] = item.createdAt;
    _lastHeadline[machineId] = headline;
    notifyListeners();

    if (_appObscured) {
      unawaited(
        _alerts?.showOsAlert(
              id: machineId.hashCode & 0x7fffffff,
              title: '$code · $alertKind',
              body: headline,
            ) ??
            Future<void>.value(),
      );
    }
  }

  void dismiss(String id) {
    final before = _toasts.length;
    _toasts.removeWhere((t) => t.id == id);
    if (_toasts.length != before) notifyListeners();
  }

  void _dismissForMachine(String machineId, {bool notify = true}) {
    final before = _toasts.length;
    _toasts.removeWhere((t) => t.machineId == machineId);
    if (notify && _toasts.length != before) notifyListeners();
  }
}

class NotificationScope extends InheritedNotifier<NotificationCenter> {
  const NotificationScope({
    required NotificationCenter center,
    required super.child,
    super.key,
  }) : super(notifier: center);

  static NotificationCenter of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NotificationScope>();
    assert(scope != null, 'NotificationScope not found');
    return scope!.notifier!;
  }
}
