import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulyaksh/main.dart';

void main() {
  testWidgets('Mulyaksh landing page renders launch content', (tester) async {
    await tester.pumpWidget(const MulyakshApp());

    expect(find.text('MULYAKSH'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('LAUNCH COUNTDOWN'), findsOneWidget);
    expect(find.text('JOIN EARLY ACCESS'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
