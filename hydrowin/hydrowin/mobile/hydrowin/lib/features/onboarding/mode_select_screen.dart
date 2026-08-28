import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:go_router/go_router.dart';

/// Устаревший экран выбора режима: сразу переходим во флот / логин.
/// Платы добавляются через PowerShell и прошивку, не через «Одна машина».
class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goFleet());
  }

  Future<void> _goFleet() async {
    final prefs = await AppPreferences.create();
    await prefs.setWorkMode(AppConstants.workModeFleet);
    await prefs.setFirstLaunchDone();
    if (!mounted) return;

    final loggedIn = await CloudScope.of(context).auth.isLoggedIn();
    if (!mounted) return;
    context.go(loggedIn ? '/fleet' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
