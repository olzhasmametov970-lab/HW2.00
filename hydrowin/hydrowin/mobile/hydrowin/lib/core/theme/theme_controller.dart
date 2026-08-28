import 'package:flutter/material.dart';
import 'package:hydrowin/data/local/app_preferences.dart';

/// Хранит и сохраняет [ThemeMode] (тёмная / светлая / система).
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    _mode = _prefs.themeMode;
  }

  final AppPreferences _prefs;
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _prefs.setThemeMode(mode);
    notifyListeners();
  }
}
