import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/constants/app_constants.dart';

void main() {
  testWidgets('app name constant is defined', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text(AppConstants.appName)),
        ),
      ),
    );
    expect(find.text('ГидроВин'), findsOneWidget);
  });
}
