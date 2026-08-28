import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/widgets/brand_logo.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    await Future<void>.delayed(AppConstants.splashDuration);
    if (!mounted) return;

    final prefs = await AppPreferences.create();
    await prefs.setFirstLaunchDone();

    if (AppConstants.isLite) {
      // Всегда домашний экран Lite (Bluetooth / демо). Не пропускать в парк —
      // иначе после демо экран «Локальная диагностика» пропадает навсегда.
      await prefs.setWorkMode(
        DemoSession.isActive
            ? AppConstants.workModeFleet
            : AppConstants.workModeSingle,
      );
      if (!mounted) return;
      context.go('/lite');
      return;
    }

    await prefs.setWorkMode(AppConstants.workModeFleet);
    if (!mounted) return;

    final cloud = CloudScope.maybeOf(context);
    final loggedIn = cloud != null && await cloud.auth.isLoggedIn();
    if (!mounted) return;
    if (loggedIn && DemoSession.isActive) {
      context.go('/fleet');
      return;
    }
    context.go(loggedIn ? '/fleet' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = AppConstants.isLite
        ? 'Только Bluetooth · без интернета и сервера'
        : 'Облако по интернету · или Bluetooth без сети';

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(size: 160),
            const SizedBox(height: 20),
            Text(AppConstants.appName),
            const SizedBox(height: 8),
            const Text('Диагностика гидравлического оборудования'),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('v1.2.0', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
