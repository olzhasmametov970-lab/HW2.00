import 'package:flutter/material.dart';

/// Ops/monitoring palette (Spraut / Prufen / Overseer vibe).
abstract final class HwColors {
  static const canvas = Color(0xFF0B0F14);
  static const surface = Color(0xFF151C24);
  static const elevated = Color(0xFF1A2330);
  static const border = Color(0xFF2A3544);

  static const primary = Color(0xFF2EC4B6);
  static const onPrimary = Color(0xFF041210);

  static const textPrimary = Color(0xFFE8EEF4);
  static const textMuted = Color(0xFF8B9BB0);

  static const ok = Color(0xFF3DDC97);
  static const warn = Color(0xFFF5A524);
  static const critical = Color(0xFFF07178);
  static const offline = Color(0xFF6B7C8F);

  // Light companion (same accent family)
  static const lightCanvas = Color(0xFFF3F6F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightElevated = Color(0xFFEEF2F6);
  static const lightBorder = Color(0xFFD5DEE8);
  static const lightText = Color(0xFF1A2330);
  static const lightMuted = Color(0xFF5A6B7D);
}
