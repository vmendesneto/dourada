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
}
