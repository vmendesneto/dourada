import 'dart:convert';
import 'dart:math';

import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/online/table_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('converte códigos de cartas recebidos em nomes completos', () {
    expect(
      normalizeServerGameMessage('Robô substituto jogou 7e.'),
      'Robô substituto jogou 7 de Espadas.',
    );
    expect(
      normalizeServerGameMessage('Robô substituto jogou Ae.'),
      'Robô substituto jogou Ás de Espadas (Espadilha).',
    );
    expect(
      normalizeServerGameMessage('Robô descartou uma carta fechada.'),
      'Robô descartou uma carta fechada.',
    );
  });

  test('mantém jogo local quando servidor não foi configurado', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final game = DouradinhaGame(random: Random(51));
    final session = TableSession(serverUrl: '');

    await session.initialize(game, preferences);

    expect(session.enabled, isFalse);
    expect(session.canPlayHere, isTrue);
    expect(session.connectionLabel, 'Mesa local');
    expect(game.phase, MatchPhase.playing);
    session.dispose();
  });

  test('aplica nome e foto de todos os jogadores no jogo', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final game = DouradinhaGame(random: Random(54));
    final entry = TableEntry(
      serverUrl: '',
      tableNumber: '1',
      playerToken: 'local',
      websocketUrl: '',
      seatIndex: 0,
      phase: LobbyTablePhase.playing,
      seats: [
        const LobbySeat(
          index: 0,
          kind: 'human',
          name: 'Maria',
          team: 0,
          connected: true,
          photoUrl: 'https://example.com/maria.jpg',
        ),
        ...List<LobbySeat?>.filled(5, null),
      ],
    );
    final session = TableSession(entry: entry);

    await session.initialize(game, preferences);

    expect(game.players.first.name, 'Maria');
    expect(game.players.first.photoUrl, 'https://example.com/maria.jpg');
    session.dispose();
  });

  test('nova partida remove número e token antigos', () async {
    SharedPreferences.setMockInitialValues({
      TableSession.tableNumberKey: '123456',
      TableSession.playerTokenKey: 'token-privado',
    });
    final preferences = await SharedPreferences.getInstance();
    final game = DouradinhaGame(random: Random(52));
    game.scores[0] = 12;
    game.phase = MatchPhase.gameOver;
    final session = TableSession(serverUrl: '');
    await session.initialize(game, preferences);

    await session.startNewMatch(game);

    expect(preferences.getString(TableSession.tableNumberKey), isNull);
    expect(preferences.getString(TableSession.playerTokenKey), isNull);
    expect(game.scores, [0, 0]);
    expect(game.phase, MatchPhase.playing);
    session.dispose();
  });

  test('pedido para robôs abre a votação recebida do servidor', () async {
    late http.Request sentRequest;
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
    final client = MockClient((request) async {
      sentRequest = request;
      return http.Response(
        '''{"phase":"waiting","seatIndex":0,"seats":[{"index":0,"kind":"human","name":"Ana","team":0,"connected":true},{"index":1,"kind":"human","name":"Beto","team":1,"connected":true},null,null,null,null],"fillBotsVotingVersion":2,"waitingStartAt":null,"gameState":null,"fillBotsVote":{"id":"vote-1","requesterSeatIndex":0,"participantSeatIndexes":[0,1],"votes":[true,null,null,null,null,null],"shownAt":[1000,null,null,null,null,null],"expiresAt":null}}''',
        200,
      );
    });
    final session = TableSession(
      entry: TableEntry(
        serverUrl: 'https://dourada.example.workers.dev',
        tableNumber: '3',
        playerToken: 'token-ana',
        websocketUrl: 'wss://dourada.example/connect',
        seatIndex: 0,
        phase: LobbyTablePhase.waiting,
        seats: seats,
        fillBotsVotingVersion: 2,
      ),
      client: client,
    );

    await session.fillRemainingWithBots();

    expect(sentRequest.url.path, '/api/tables/3/fill-bots');
    expect(
      (jsonDecode(sentRequest.body)
          as Map<String, dynamic>)['humanSeatIndexes'],
      [0, 1],
    );
    expect(session.fillBotsVote?.id, 'vote-1');
    expect(session.fillBotsVote?.requesterSeatIndex, 0);
    expect(session.fillBotsVote?.participantSeatIndexes, [0, 1]);
    expect(session.fillBotsVote?.expiresAt, isNull);
    expect(session.requestingFillBotsVote, isFalse);
    session.dispose();
  });

  test('não envia pedido para servidor sem confirmação de exibição', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      return http.Response('{}', 500);
    });
    final session = TableSession(
      entry: TableEntry(
        serverUrl: 'https://dourada.example.workers.dev',
        tableNumber: '3',
        playerToken: 'token-ana',
        websocketUrl: 'wss://dourada.example/connect',
        seatIndex: 0,
        phase: LobbyTablePhase.waiting,
        seats: [
          const LobbySeat(
            index: 0,
            kind: 'human',
            name: 'Ana',
            team: 0,
            connected: true,
          ),
          ...List<LobbySeat?>.filled(5, null),
        ],
      ),
      client: client,
    );

    await session.fillRemainingWithBots();

    expect(requestCount, 0);
    expect(
      session.errorMessage,
      contains('servidor da mesa precisa ser atualizado'),
    );
    session.dispose();
  });

  test('sair avisa o servidor e apaga a possibilidade de retorno', () async {
    SharedPreferences.setMockInitialValues({
      TableSession.tableNumberKey: '4',
      TableSession.playerTokenKey: 'token-privado',
      LobbyService.seatIndexKey: 2,
    });
    late http.Request sentRequest;
    final client = MockClient((request) async {
      sentRequest = request;
      return http.Response('{"declined":true,"tableClosed":false}', 200);
    });
    final entry = TableEntry(
      serverUrl: 'https://dourada.example.workers.dev',
      tableNumber: '4',
      playerToken: 'token-privado',
      websocketUrl: 'wss://dourada.example.workers.dev/connect',
      seatIndex: 2,
      phase: LobbyTablePhase.playing,
      seats: List<LobbySeat?>.filled(6, null),
    );
    final session = TableSession(entry: entry, client: client);

    await session.leaveTable();

    expect(sentRequest.method, 'POST');
    expect(sentRequest.url.path, '/api/tables/4/leave');
    expect(sentRequest.body, contains('token-privado'));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(TableSession.tableNumberKey), isNull);
    expect(preferences.getString(TableSession.playerTokenKey), isNull);
    expect(preferences.getInt(LobbyService.seatIndexKey), isNull);
    session.dispose();
  });

  test('cadeira perdida limpa a sessão e volta a ser indisponível só quando o servidor rejeita o token', () async {
    SharedPreferences.setMockInitialValues({
      TableSession.tableNumberKey: '4',
      TableSession.playerTokenKey: 'token-antigo',
      LobbyService.seatIndexKey: 0,
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/api/tables/4/join');
      return http.Response('{"error":"Sessão inválida"}', 401);
    });
    final session = TableSession(
      entry: TableEntry(
        serverUrl: 'https://dourada.example.workers.dev',
        tableNumber: '4',
        playerToken: 'token-antigo',
        websocketUrl: 'wss://dourada.example.workers.dev/connect',
        seatIndex: 0,
        phase: LobbyTablePhase.waiting,
        seats: List<LobbySeat?>.filled(6, null),
      ),
      client: client,
    );

    await session.pausePresence();
    await session.resumePresence();

    expect(session.seatUnavailable, isTrue);
    expect(session.errorMessage, isNull);
    await session.clearUnavailableSeat();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(TableSession.tableNumberKey), isNull);
    expect(preferences.getString(TableSession.playerTokenKey), isNull);
    expect(preferences.getInt(LobbyService.seatIndexKey), isNull);
    session.dispose();
  });

  test('chat local guarda, normaliza e limita mensagens', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final game = DouradinhaGame(random: Random(81));
    final session = TableSession(
      entry: TableEntry(
        serverUrl: '',
        tableNumber: '1',
        playerToken: 'local',
        websocketUrl: '',
        seatIndex: 0,
        phase: LobbyTablePhase.playing,
        seats: [
          const LobbySeat(
            index: 0,
            kind: 'human',
            name: 'Ana',
            team: 0,
            connected: true,
          ),
          ...List<LobbySeat?>.filled(5, null),
        ],
      ),
    );
    await session.initialize(game, preferences);

    expect(session.sendChatMessage('   Olá   mesa   '), isTrue);
    expect(session.chatMessages.single.author, 'Ana');
    expect(session.chatMessages.single.text, 'Olá mesa');
    expect(session.sendChatMessage('   '), isFalse);

    final longText = List.filled(
      TableChatMessage.maxTextLength + 20,
      'x',
    ).join();
    expect(session.sendChatMessage(longText), isTrue);
    expect(
      session.chatMessages.last.text.length,
      TableChatMessage.maxTextLength,
    );
    session.dispose();
  });
}
