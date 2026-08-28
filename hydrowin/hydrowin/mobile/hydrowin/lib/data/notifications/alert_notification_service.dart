import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';

/// Local alerts: BLE sensor summary + OS toast (Windows / Android).
/// Web: no-op stubs so desktop/web builds stay simple.
class AlertNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _liveSummaryTitle;
  String? _liveSummaryBody;

  static const _channelId = 'hydrowin_alerts';
  static const _channelName = 'ГидроВин · аварии';
  static const _liveChannelId = 'hydrowin_live';
  static const _liveChannelName = 'ГидроВин · живые датчики';
  static const _liveId = 9001;

  Future<void> init({bool requestPermission = true}) async {
    if (kIsWeb || _ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const windows = WindowsInitializationSettings(
        appName: 'HydroWin',
        appUserModelId: 'HydroWin.Desktop',
        guid: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      );
      const init = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        windows: windows,
      );
      await _plugin.initialize(init);

      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Предупреждения и аварии гидростанций',
            importance: Importance.high,
          ),
        );
        // Отдельный канал: постоянная сводка на экране блокировки без звука.
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _liveChannelId,
            _liveChannelName,
            description: 'Текущие значения датчиков (шторка / lock screen)',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
        if (requestPermission) {
          await androidPlugin?.requestNotificationsPermission();
        }
      }
      if (!kIsWeb && Platform.isIOS && requestPermission) {
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('AlertNotificationService.init: $e');
    }
  }

  /// Ongoing BLE / live sensor strip on lock screen & notification shade.
  Future<void> updateLiveSummary(String title, String body) async {
    _liveSummaryTitle = title;
    _liveSummaryBody = body;
    if (!_ready || kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _plugin.show(
          _liveId,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _liveChannelId,
              _liveChannelName,
              channelDescription:
                  'Текущие значения датчиков (шторка / lock screen)',
              importance: Importance.low,
              priority: Priority.low,
              ongoing: true,
              onlyAlertOnce: true,
              autoCancel: false,
              showWhen: true,
              visibility: NotificationVisibility.public,
              category: AndroidNotificationCategory.status,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: 'ГидроВин',
              ),
            ),
          ),
        );
        return;
      }
      if (Platform.isIOS) {
        // iOS не даёт «вечную» шторку как Android, но обновляемое уведомление
        // видно на lock screen при разрешённых уведомлениях.
        await _plugin.show(
          _liveId,
          title,
          body,
          const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: false,
              presentSound: false,
              interruptionLevel: InterruptionLevel.passive,
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('updateLiveSummary: $e');
    }
  }

  Future<void> clearLiveSummary() async {
    _liveSummaryTitle = null;
    _liveSummaryBody = null;
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(_liveId);
  }

  final Map<int, String> _lastAlertKey = {};

  /// BLE / local telemetry: только аварии (critical / обрыв / КЗ).
  Future<void> maybeNotify(LiveSensorReading reading) async {
    if (!_ready || kIsWeb) return;
    final isAccident = reading.status.name == 'critical' ||
        reading.loopFault.name == 'open' ||
        reading.loopFault.name == 'short';
    if (!isAccident) {
      _lastAlertKey.remove(reading.config.channelIndex);
      return;
    }
    final key = '${reading.status.name}_${reading.loopFault.name}';
    if (_lastAlertKey[reading.config.channelIndex] == key) return;
    _lastAlertKey[reading.config.channelIndex] = key;

    await showOsAlert(
      id: 1000 + reading.config.channelIndex,
      title: reading.alertTitle,
      body: reading.alertDetailBody,
    );
  }

  /// OS toast (Windows Action Center / Android / iOS). Used when app is minimized.
  Future<void> showOsAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    if (!_ready || kIsWeb) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Предупреждения и аварии гидростанций',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('showOsAlert: $e');
    }
  }

  String? get liveSummaryTitle => _liveSummaryTitle;
  String? get liveSummaryBody => _liveSummaryBody;
}
