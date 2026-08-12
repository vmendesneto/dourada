import 'package:dourada/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inicia a mesa da Douradinha', (tester) async {
    await tester.pumpWidget(const DouradinhaApp());
    await tester.pump();

    expect(find.text('VOCÊ'), findsOneWidget);
    expect(find.text('TRUCO!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
