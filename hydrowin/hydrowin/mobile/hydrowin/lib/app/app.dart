import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hydrowin/app/notification_center.dart';
import 'package:hydrowin/app/router.dart';
import 'package:hydrowin/app/theme_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/features/notifications/fleet_alert_monitor.dart';
import 'package:hydrowin/features/notifications/side_toast_host.dart';

class HydroWinApp extends StatelessWidget {
  const HydroWinApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: themeCtrl,
      builder: (context, _) {
        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeCtrl.mode,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: appRouter,
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            final host = SideToastHost(child: content);
            if (AppConstants.isLite) {
              return _LifecycleBinder(
                child: DemoSession.isActive
                    ? FleetAlertMonitor(child: host)
                    : host,
              );
            }
            return _LifecycleBinder(
              child: FleetAlertMonitor(child: host),
            );
          },
        );
      },
    );
  }
}

class _LifecycleBinder extends StatefulWidget {
  const _LifecycleBinder({required this.child});

  final Widget child;

  @override
  State<_LifecycleBinder> createState() => _LifecycleBinderState();
}

class _LifecycleBinderState extends State<_LifecycleBinder>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationScope.of(context).setLifecycle(state);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
