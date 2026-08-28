import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart';

/// Периодическое обновление экрана по настройке «Частота обновления».
mixin PollIntervalRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  TelemetrySession? _session;
  int? _boundPollSeconds;

  /// Вызывается при каждом тике таймера (и при первом запуске — отдельно).
  Future<void> onPollIntervalRefresh();

  void bindPollIntervalRefresh() {
    _session?.removeListener(_onSessionChanged);
    _session = AppScope.of(context);
    _session!.addListener(_onSessionChanged);
    _restartPollTimer();
  }

  void unbindPollIntervalRefresh() {
    _session?.removeListener(_onSessionChanged);
    _session = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _boundPollSeconds = null;
  }

  void _onSessionChanged() {
    final seconds = _session?.pollSeconds;
    if (seconds != null && seconds != _boundPollSeconds) {
      _restartPollTimer();
    }
  }

  void _restartPollTimer() {
    _pollTimer?.cancel();
    final seconds = (_session?.pollSeconds ?? AppConstants.defaultPollSeconds)
        .clamp(AppConstants.minPollSeconds, AppConstants.maxPollSeconds);
    _boundPollSeconds = seconds;
    if (mounted) {
      unawaited(onPollIntervalRefresh());
    }
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (mounted) {
        unawaited(onPollIntervalRefresh());
      }
    });
  }
}
