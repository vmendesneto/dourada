import 'dart:math';

import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/online/table_session.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
