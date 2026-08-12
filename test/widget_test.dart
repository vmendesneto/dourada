import 'package:dourada/main.dart';
import 'package:dourada/ui/game_page.dart';
import 'package:dourada/ui/lobby_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lobby se adapta a uma tela estreita', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DouradinhaApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('entrar-em-uma-mesa')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abre o lobby e só entra na mesa depois do clique',
      (tester) async {
    await tester.pumpWidget(const DouradinhaApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('entrar-em-uma-mesa')), findsOneWidget);
    expect(find.text('TRUCO!'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    expect(find.text('VOCÊ'), findsWidgets);
    expect(find.text('TRUCO!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('barra do resultado diminui durante os cinco segundos',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

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

  testWidgets('retomada escolhe não voltar depois de vinte segundos',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ResumeDialogHarness()));
    await tester.tap(find.text('ABRIR'));
    await tester.pump();

    expect(find.text('VOLTAR PARA A MESA 4?'), findsOneWidget);
    expect(find.textContaining('20 segundos'), findsOneWidget);

    for (var second = 0; second < 19; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('1 segundo.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('NÃO VOLTOU'), findsOneWidget);
    expect(find.byType(ResumeTableDialog), findsNothing);
  });
}

class _ResumeDialogHarness extends StatefulWidget {
  const _ResumeDialogHarness();

  @override
  State<_ResumeDialogHarness> createState() => _ResumeDialogHarnessState();
}

class _ResumeDialogHarnessState extends State<_ResumeDialogHarness> {
  String result = '';

  Future<void> open() async {
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ResumeTableDialog(tableNumber: 4),
    );
    if (mounted) {
      setState(() => result = resume == true ? 'VOLTOU' : 'NÃO VOLTOU');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(onPressed: open, child: const Text('ABRIR')),
          Text(result),
        ],
      ),
    );
  }
}
