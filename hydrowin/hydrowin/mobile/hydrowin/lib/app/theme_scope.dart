import 'package:flutter/material.dart';
import 'package:hydrowin/core/theme/theme_controller.dart';

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    required ThemeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found');
    return scope!.notifier!;
  }

  static ThemeController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope not found');
    return scope!.notifier!;
  }
}
