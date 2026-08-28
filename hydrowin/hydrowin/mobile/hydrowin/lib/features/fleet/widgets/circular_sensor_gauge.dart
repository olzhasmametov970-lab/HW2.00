import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';

/// Круговой индикатор в духе стрелочного прибора (значение + зона нормы/аварии).
class CircularSensorGauge extends StatelessWidget {
  const CircularSensorGauge({
    required this.value,
    required this.config,
    this.status = SensorStatusLevel.ok,
    this.size = 96,
    super.key,
  });

  final double value;
  final SensorConfig config;
  final SensorStatusLevel status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.statusColor(status, context);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          value: value,
          min: config.scaleMin,
          max: config.scaleMax,
          normMax: config.normMax,
          warnHigh: config.warnHigh ?? config.normMax,
          criticalHigh: config.criticalHigh,
          accent: accent,
          track: theme.colorScheme.outlineVariant,
          face: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.normMax,
    required this.warnHigh,
    required this.criticalHigh,
    required this.accent,
    required this.track,
    required this.face,
  });

  final double value;
  final double min;
  final double max;
  final double normMax;
  final double warnHigh;
  final double criticalHigh;
  final Color accent;
  final Color track;
  final Color face;

  static const _start = math.pi * 0.75; // 135°
  static const _sweep = math.pi * 1.5; // 270°

  double _t(double v) {
    final span = (max - min).abs() < 1e-6 ? 1.0 : (max - min);
    return ((v - min) / span).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.42;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Фон циферблата
    canvas.drawCircle(c, r + 4, Paint()..color = face);

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, bg);

    // Зелёная зона до нормы, янтарная до warn, красная до max
    void arc(double fromT, double toT, Color color) {
      if (toT <= fromT) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.butt
        ..color = color;
      canvas.drawArc(
        rect,
        _start + _sweep * fromT,
        _sweep * (toT - fromT),
        false,
        paint,
      );
    }

    final tNorm = _t(normMax);
    final tWarn = _t(warnHigh);
    final tCrit = _t(criticalHigh);
    arc(0, tNorm, HwColors.ok);
    arc(tNorm, tWarn, HwColors.warn);
    arc(tWarn, math.max(tCrit, tWarn), HwColors.critical);
    if (tCrit < 1) arc(tCrit, 1, HwColors.critical.withValues(alpha: 0.7));

    // Риски
    final tickPaint = Paint()
      ..color = track
      ..strokeWidth = 1.5;
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * (i / 10);
      final outer = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      final inner = Offset(
        c.dx + math.cos(a) * (r - (i % 5 == 0 ? 10 : 6)),
        c.dy + math.sin(a) * (r - (i % 5 == 0 ? 10 : 6)),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Стрелка
    final ta = _start + _sweep * _t(value);
    final needle = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final tip = Offset(
      c.dx + math.cos(ta) * (r - 14),
      c.dy + math.sin(ta) * (r - 14),
    );
    canvas.drawLine(c, tip, needle);
    canvas.drawCircle(c, 5, Paint()..color = accent);
    canvas.drawCircle(c, 2.2, Paint()..color = face);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) {
    return old.value != value ||
        old.min != min ||
        old.max != max ||
        old.accent != accent;
  }
}
