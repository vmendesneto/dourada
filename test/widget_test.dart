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
    expect(find.byKey(const ValueKey('entrar-rapido')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrada rápida escolhe a primeira mesa aguardando',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final service = _HangingCancelLobbyService(
      tables: [
        _lobbyTable(1, LobbyTablePhase.empty),
        _lobbyTable(2, LobbyTablePhase.playing, playerCount: 6),
        _lobbyTable(3, LobbyTablePhase.waiting, playerCount: 2),
        _lobbyTable(4, LobbyTablePhase.waiting, playerCount: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(
          service: service,
          authService: FakeAuthService(signedIn: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('DOURADA'), findsOneWidget);
    expect(find.text('LOBBY DOURADINHA'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('entrar-rapido')));
    await tester.pumpAndSettle();

    expect(service.joinedTableNumber, 3);
    expect(find.byType(GamePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
    expect(find.byKey(const ValueKey('dialogo-trocar-imagem')), findsOneWidget);
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('escolher-camera-fotos')));
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
    expect(find.byKey(const ValueKey('dialogo-trocar-imagem')), findsOneWidget);
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('escolher-camera-fotos')));
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
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('escolher-camera-fotos')), findsOneWidget);
    expect(find.byKey(const ValueKey('escolher-avatar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voltar-escolha-imagem')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    expect(find.byKey(const ValueKey('escolher-camera-fotos')), findsOneWidget);
    expect(find.byKey(const ValueKey('escolher-avatar')), findsOneWidget);
    expect(find.text('Novo avatar selecionado.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
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
    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
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

  testWidgets('anima a foto do humano quando chega a vez dele', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedGame = DouradinhaGame()..currentPlayerIndex = 1;
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

    final highlight =
        find.byKey(const ValueKey('animacao-turno-jogador-local'));
    expect(highlight, findsOneWidget);
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(
                of: highlight, matching: find.byType(AnimatedScale)),
          )
          .scale,
      1,
    );

    final dynamic pageState = tester.state(find.byType(GamePage));
    final dynamic game = pageState.game;
    game.currentPlayerIndex = game.humanPlayerIndex;
    game.notifyListeners();
    await tester.pump();

    final activeScale = tester.widget<AnimatedScale>(
      find.descendant(of: highlight, matching: find.byType(AnimatedScale)),
    );
    final activeContainer = tester.widget<AnimatedContainer>(
      find.descendant(of: highlight, matching: find.byType(AnimatedContainer)),
    );
    final foreground = activeContainer.foregroundDecoration! as BoxDecoration;
    expect(activeScale.scale, 1.08);
    expect(activeScale.duration, const Duration(milliseconds: 250));
    expect(foreground.border!.top.width, 3);

    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('todos os humanos do trio veem a decisão conjunta do desafio',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _challengeVoteEntry())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('TRUCO!'), findsWidgets);
    expect(
      find.textContaining('o trio corre ao fim do tempo'),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('tempo-resposta-desafio')), findsOneWidget);
    expect(find.text('Ana • Aguardando'), findsOneWidget);
    expect(find.text('Carla • Correu'), findsOneWidget);
    expect(find.byKey(const ValueKey('aceitar-desafio')), findsOneWidget);
    expect(find.byKey(const ValueKey('correr-desafio')), findsOneWidget);
    expect(find.byKey(const ValueKey('aumentar-desafio')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('mostra a imagem da resposta para todos na mesa', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _challengeNoticeEntry(true))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsOneWidget);
    expect(find.byKey(const ValueKey('imagem-desafio-correu')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _challengeNoticeEntry(false))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('imagem-desafio-correu')), findsOneWidget);
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('espera o gif do pedido terminar antes de mostrar a resposta',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: GamePage(entry: _challengeVoteEntry())),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('imagem-gif-desafio-2')),
      findsOneWidget,
    );
    final dynamic pageState = tester.state(find.byType(GamePage));
    final game = pageState.game as DouradinhaGame;
    game.acceptHumanChallenge();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('imagem-gif-desafio-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsNothing);

    await tester.pump(
      DouradinhaGame.challengeAnimationDuration -
          const Duration(milliseconds: 1),
    );
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('imagem-gif-desafio-2')), findsNothing);
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsOneWidget);

    await tester.pump(
      DouradinhaGame.challengeNoticeDuration - const Duration(milliseconds: 1),
    );
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('imagem-desafio-aceito')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
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

  testWidgets('decisão da mão de dez não cobre os parceiros no celular',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedGame = DouradinhaGame()
      ..scores[0] = 10
      ..phase = MatchPhase.handFinished;
    savedGame.startNextHand();
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

    final decision = find.byKey(const ValueKey('decisao-mao-de-dez'));
    final decisionRect = tester.getRect(decision);
    expect(decision, findsOneWidget);
    expect(decisionRect.height, lessThanOrEqualTo(120));
    expect(find.byKey(const ValueKey('correr-mao-de-dez')), findsOneWidget);
    expect(find.byKey(const ValueKey('jogar-mao-de-dez')), findsOneWidget);

    for (final playerIndex in [2, 4]) {
      final partnerCards = find.byKey(ValueKey('cartas-parceiro-$playerIndex'));
      expect(partnerCards, findsOneWidget);
      expect(decisionRect.overlaps(tester.getRect(partnerCards)), isFalse);
    }
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
        attempt < 30 && find.text('DOURADA').evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('DOURADA'), findsOneWidget);
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

  testWidgets('tempo da votação espera o diálogo aparecer para o humano',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: GamePage(
          entry: _fillBotsVoteEntry(seatIndex: 1, timerStarted: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('O tempo de resposta ainda não começou'), findsOneWidget);
    expect(
        find.textContaining('Preparando o tempo de resposta'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('tempo-votacao-robos')),
          )
          .value,
      isNull,
    );
    expect(find.byKey(const ValueKey('aceitar-robos')), findsNothing);
    expect(find.byKey(const ValueKey('recusar-robos')), findsNothing);

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

TableEntry _fillBotsVoteEntry({
  required int seatIndex,
  bool timerStarted = true,
}) {
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
      id: 'vote-1',
      requesterSeatIndex: 0,
      participantSeatIndexes: const [0, 1],
      votes: const [true, null, null, null, null, null],
      shownAt: [
        DateTime.now(),
        timerStarted ? DateTime.now() : null,
        null,
        null,
        null,
        null,
      ],
      expiresAt:
          timerStarted ? DateTime.now().add(const Duration(seconds: 10)) : null,
    ),
    fillBotsVotingVersion: 2,
  );
}

TableEntry _challengeVoteEntry() {
  final game = DouradinhaGame(humanPlayerIndex: 0)
    ..currentPlayerIndex = 1
    ..pendingChallenge = const Challenge(
      challengerTeam: 1,
      challengerPlayer: 1,
      targetTeam: 0,
      requestedValue: 2,
      responderPlayer: 2,
    )
    ..statusMessage = 'Beto pediu TRUCO!';
  game.history.insert(0, game.statusMessage);
  final seats = <LobbySeat?>[
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
    const LobbySeat(
      index: 2,
      kind: 'human',
      name: 'Carla',
      team: 0,
      connected: true,
    ),
    ...List<LobbySeat?>.filled(3, null),
  ];
  return TableEntry(
    serverUrl: 'http://127.0.0.1:1',
    tableNumber: '1',
    playerToken: 'token-0',
    websocketUrl: 'ws://127.0.0.1:1/connect',
    seatIndex: 0,
    phase: LobbyTablePhase.playing,
    seats: seats,
    challengeVotingVersion: 1,
    challengeVote: TeamChallengeVote(
      id: 'challenge-1',
      targetTeam: 0,
      requestedValue: 2,
      challengerPlayer: 1,
      expiresAt: DateTime.now().add(const Duration(seconds: 15)),
      participantSeatIndexes: [0, 2],
      votes: [null, null, ChallengeVoteChoice.fold, null, null, null],
    ),
    gameState: game.toJson(),
  );
}

TableEntry _challengeNoticeEntry(bool accepted) {
  final game = DouradinhaGame()
    ..challengeNotice = accepted
        ? 'O trio adversário aceitou o desafio.'
        : 'O trio adversário correu do desafio.'
    ..challengeNoticeAccepted = accepted;
  return TableEntry(
    serverUrl: 'http://127.0.0.1:1',
    tableNumber: '1',
    playerToken: 'token-0',
    websocketUrl: 'ws://127.0.0.1:1/connect',
    seatIndex: 0,
    phase: LobbyTablePhase.playing,
    seats: List<LobbySeat?>.filled(6, null),
    gameState: game.toJson(),
  );
}

LobbyTable _lobbyTable(
  int tableNumber,
  LobbyTablePhase phase, {
  int playerCount = 0,
}) =>
    LobbyTable(
      tableNumber: tableNumber,
      phase: phase,
      playerCount: playerCount,
      humanCount: playerCount,
      botCount: 0,
      capacity: 6,
      seats: List<LobbySeat?>.filled(6, null),
    );

class _HangingCancelLobbyService extends LobbyService {
  _HangingCancelLobbyService({List<LobbyTable>? tables})
      : _tables = tables ??
            List.generate(
                10, (index) => _lobbyTable(index + 1, LobbyTablePhase.empty)),
        super(serverUrl: '') {
    _controller = StreamController<List<LobbyTable>>();
    _controller.onListen = () => _controller.add(_tables);
    _controller.onCancel = () => Completer<void>().future;
  }

  late final StreamController<List<LobbyTable>> _controller;
  final List<LobbyTable> _tables;
  bool joinCalled = false;
  int? joinedTableNumber;

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
    joinedTableNumber = tableNumber;
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
