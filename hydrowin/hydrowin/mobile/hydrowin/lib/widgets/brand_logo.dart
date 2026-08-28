import 'package:flutter/material.dart';

/// Фирменный знак ГидроВин / HydroWin.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 120});

  final double size;

  static const assetPath = 'assets/branding/hydrowin_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'ГидроВин / HydroWin',
    );
  }
}
