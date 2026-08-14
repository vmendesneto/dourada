import 'dart:async';
import 'dart:convert';

import 'package:dourada/auth/auth_service.dart';
import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/main.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/ui/game_page.dart';
import 'package:dourada/ui/lobby_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';

void main() {
  testWidgets('entra na mesa mesmo se o lobby nao confirmar o fechamento',
      (tester) async {
    final service = _HangingCancelLobbyService();
    final authService = FakeAuthService(signedIn: true);
    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(service: service, authService: authService),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pump();

    expect(service.joinCalled, isTrue);
    await tester.pump();
    expect(find.byType(GamePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('perfil só altera Firebase ao salvar e permite cancelar',
      (tester) async {
    final authService = FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(
          service: _HangingCancelLobbyService(),
          authService: authService,
          profileImagePicker: () async => SelectedProfileImage(
            bytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
            contentType: 'image/png',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('entrar-conta')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('entrar-conta')));
    await tester.pump();

    expect(authService.signInCalls, 1);
    expect(find.byKey(const ValueKey('abrir-perfil')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();

    expect(find.text('jogador@exemplo.com'), findsOneWidget);
    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('email-perfil')),
    );
    expect(emailField.enabled, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('nome-perfil')),
      'Nome descartado',
    );
    expect(find.byKey(const ValueKey('foto-perfil')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.text('Nova foto selecionada.'), findsOneWidget);
    expect(authService.updateProfileCalls, 0);
    await tester.tap(find.byKey(const ValueKey('cancelar-perfil')));
    await tester.pumpAndSettle();

    expect(authService.updateProfileCalls, 0);
    expect(authService.currentUser?.displayName, 'Jogador');
    expect(authService.savedImage, isNull);

    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nome-perfil')),
      'Novo Nome',
    );
    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('salvar-perfil')));
    await tester.pumpAndSettle();

    expect(authService.updateProfileCalls, 1);
    expect(authService.savedName, 'Novo Nome');
    expect(authService.savedImage?.contentType, 'image/png');
    expect(authService.savedImage?.bytes, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('sair-conta')));
    await tester.pump();

    expect(authService.signOutCalls, 1);
    expect(find.byKey(const ValueKey('entrar-conta')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('avatar escolhido só fica permanente depois de salvar',
      (tester) async {
    final authService = FakeAuthService(signedIn: true);
    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(
          service: _HangingCancelLobbyService(),
          authService: authService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final avatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
    await tester.ensureVisible(avatar);
    await tester.tap(avatar);
    await tester.pump();

    expect(find.text('Novo avatar selecionado.'), findsOneWidget);
    expect(authService.updateProfileCalls, 0);

    await tester.tap(find.byKey(const ValueKey('cancelar-perfil')));
    await tester.pumpAndSettle();
    expect(authService.savedAvatarAsset, isNull);
    expect(authService.currentUser?.photoUrl, isEmpty);

    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final savedAvatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
    await tester.ensureVisible(savedAvatar);
    await tester.tap(savedAvatar);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('salvar-perfil')));
    await tester.pumpAndSettle();

    expect(authService.updateProfileCalls, 1);
    expect(authService.savedImage, isNull);
    expect(authService.savedAvatarAsset, profileAvatarAssets[8]);
    expect(
      humanAvatarAssetFromPhotoUrl(authService.currentUser?.photoUrl),
      profileAvatarAssets[8],
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('visitante precisa fazer login antes de entrar na mesa',
      (tester) async {
    final service = _HangingCancelLobbyService();
    final authService = FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(service: service, authService: authService),
      ),
    );
    await tester.pump();

    expect(find.text('FAÇA LOGIN PARA ENTRAR'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pump();

    expect(authService.signInCalls, 1);
    expect(service.joinCalled, isFalse);
    expect(find.byType(GamePage), findsNothing);

    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pump();
    expect(authService.idTokenCalls, 1);
    expect(service.joinCalled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('abre o lobby e só entra na mesa depois do clique',
      (tester) async {
    await tester.pumpWidget(
      DouradinhaApp(authService: FakeAuthService(signedIn: true)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('entrar-em-uma-mesa')), findsOneWidget);
    expect(find.text('TRUCO!'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nome-jogador-local')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('nome-jogador-local')))
          .data,
      'Jogador',
    );
    expect(find.text('TRUCO!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mesa de jogo se adapta a telefone sem sobreposicoes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      DouradinhaApp(authService: FakeAuthService(signedIn: true)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nome-jogador-local')), findsOneWidget);
    expect(find.byKey(const ValueKey('sair-da-mesa')), findsOneWidget);
    expect(find.text('TRUCO!'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('cabecalho-mesa-mobile')))
          .height,
      72,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('esconde a carta na mão e mantém o verso ao descartá-la',
      (tester) async {
    final savedGame = DouradinhaGame()..currentPlayerIndex = 0;
    final card = savedGame.players[0].hand.first;
    SharedPreferences.setMockInitialValues({
      'douradinha_partida_em_andamento_v1': jsonEncode(savedGame.toJson()),
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await tester.pumpWidget(
      DouradinhaApp(authService: FakeAuthService(signedIn: true)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    final hideButton = find.byKey(ValueKey('esconder-carta-${card.code}'));
    expect(hideButton, findsOneWidget);
    await tester.tap(hideButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('carta-escondida')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('carta-escondida')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('carta-jogada-escondida-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desabilita esconder na mão de dez', (tester) async {
    final savedGame = DouradinhaGame()
      ..currentPlayerIndex = 0
      ..scores[0] = 10;
    savedGame.chooseToPlayTenHand();
    final card = savedGame.players[0].hand.first;
    SharedPreferences.setMockInitialValues({
      'douradinha_partida_em_andamento_v1': jsonEncode(savedGame.toJson()),
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await tester.pumpWidget(
      DouradinhaApp(authService: FakeAuthService(signedIn: true)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    final hideButton = find.byKey(ValueKey('esconder-carta-${card.code}'));
    expect(tester.widget<InkWell>(hideButton).onTap, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saida confirmada volta ao lobby e encerra a sessao',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      DouradinhaApp(authService: FakeAuthService(signedIn: true)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('entrar-em-uma-mesa')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sair-da-mesa')));
    await tester.pumpAndSettle();
    expect(find.text('SAIR DA MESA?'), findsOneWidget);
    expect(find.textContaining('Não será possível retornar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirmar-saida-mesa')));
    for (var attempt = 0;
        attempt < 30 && find.text('LOBBY DOURADINHA').evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('LOBBY DOURADINHA'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GamePage), findsNothing);
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

  testWidgets('solicitante aguarda os votos para completar com robôs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _fillBotsVoteEntry(seatIndex: 0))),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('dialogo-votacao-robos')), findsOneWidget);
    expect(find.text('AGUARDANDO RESPOSTAS'), findsOneWidget);
    expect(find.textContaining('Você pediu para completar'), findsOneWidget);
    expect(find.byKey(const ValueKey('aceitar-robos')), findsNothing);
    expect(find.byKey(const ValueKey('recusar-robos')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('outro humano recebe o pedido com avatares e ações',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _fillBotsVoteEntry(seatIndex: 1))),
    );
    await tester.pump();

    expect(find.text('COMPLETAR COM ROBÔS?'), findsOneWidget);
    expect(find.textContaining('Ana pediu para completar'), findsOneWidget);
    expect(find.byKey(const ValueKey('aceitar-robos')), findsOneWidget);
    expect(find.byKey(const ValueKey('recusar-robos')), findsOneWidget);
    expect(find.text('Pediu'), findsOneWidget);
    expect(find.text('Aguardando'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
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

TableEntry _fillBotsVoteEntry({required int seatIndex}) {
  final seats = [
    const LobbySeat(
      index: 0,
      kind: 'human',
      name: 'Ana',
      team: 0,
      connected: true,
    ),
    const LobbySeat(
      index: 1,
      kind: 'human',
      name: 'Beto',
      team: 1,
      connected: true,
    ),
    ...List<LobbySeat?>.filled(4, null),
  ];
  return TableEntry(
    serverUrl: 'http://127.0.0.1:1',
    tableNumber: '1',
    playerToken: 'token-$seatIndex',
    websocketUrl: 'ws://127.0.0.1:1/connect',
    seatIndex: seatIndex,
    phase: LobbyTablePhase.waiting,
    seats: seats,
    fillBotsVote: FillBotsVote(
      requesterSeatIndex: 0,
      participantSeatIndexes: const [0, 1],
      votes: const [true, null, null, null, null, null],
      expiresAt: DateTime.now().add(const Duration(seconds: 10)),
    ),
  );
}

class _HangingCancelLobbyService extends LobbyService {
  _HangingCancelLobbyService() : super(serverUrl: '') {
    _controller = StreamController<List<LobbyTable>>();
    _controller.onListen = () => _controller.add(_tables);
    _controller.onCancel = () => Completer<void>().future;
  }

  late final StreamController<List<LobbyTable>> _controller;
  bool joinCalled = false;

  static final _tables = List.generate(
    10,
    (index) => LobbyTable(
      tableNumber: index + 1,
      phase: LobbyTablePhase.empty,
      playerCount: 0,
      humanCount: 0,
      botCount: 0,
      capacity: 6,
      seats: List<LobbySeat?>.filled(6, null),
    ),
  );

  @override
  Stream<List<LobbyTable>> watchTables() => _controller.stream;

  @override
  Future<TableEntry> joinTable(
    int tableNumber, {
    String? firebaseIdToken,
    String? playerName,
    String? playerPhotoUrl,
  }) async {
    joinCalled = true;
    return super.joinTable(
      tableNumber,
      firebaseIdToken: firebaseIdToken,
      playerName: playerName,
      playerPhotoUrl: playerPhotoUrl,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
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
