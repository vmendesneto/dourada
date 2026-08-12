import 'package:dourada/main.dart';
import 'package:dourada/ui/game_page.dart';
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

  testWidgets('barra do resultado diminui durante os cinco segundos',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HandResultProgress(color: Colors.amber),
        ),
      ),
    );

    LinearProgressIndicator progress() => tester.widget(
          find.byKey(const ValueKey('barra-resultado-mao')),
        );

    expect(progress().value, 1);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(progress().value, closeTo(.5, .02));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(progress().value, closeTo(0, .001));
  });
}
