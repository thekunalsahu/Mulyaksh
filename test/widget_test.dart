import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulyaksh/main.dart';

void main() {
  testWidgets('Mulyaksh landing page renders launch content', (tester) async {
    await tester.pumpWidget(const MulyakshApp());

    expect(find.text('Mulyaksh'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('LAUNCH COUNTDOWN'), findsOneWidget);
    expect(find.text('JOIN EARLY ACCESS'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Mulyaksh landing page fits mobile viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(const MulyakshApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Mulyaksh'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
