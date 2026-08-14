import 'dart:convert';

import 'package:dourada/online/lobby_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normaliza caracteres invisiveis na URL do servidor', () {
    final service = LobbyService(
      serverUrl: '\uFEFF  https://dourada.example.workers.dev///\n',
    );

    expect(service.serverUrl, 'https://dourada.example.workers.dev');
    service.dispose();
  });

  test('decodifica atualização enviada pelo WebSocket do lobby', () {
    final tables = LobbyService.decodeTables(jsonEncode({
      'type': 'lobby',
      'tables': [
        {
          'tableNumber': 1,
          'status': 'waiting',
          'playerCount': 1,
          'humanCount': 1,
          'botCount': 0,
          'capacity': 6,
          'seats': [
            {
              'index': 0,
              'kind': 'human',
              'name': 'Jogador 1',
              'photoUrl': 'https://example.com/jogador.jpg',
              'team': 0,
              'connected': true,
            },
            null,
            null,
            null,
            null,
            null,
          ],
        },
      ],
    }));

    expect(tables, hasLength(1));
    expect(tables.single.phase, LobbyTablePhase.waiting);
    expect(tables.single.humanCount, 1);
    expect(tables.single.seats.first?.connected, isTrue);
    expect(
      tables.single.seats.first?.photoUrl,
      'https://example.com/jogador.jpg',
    );
  });

  test('envia token Firebase e nome ao ocupar uma nova cadeira', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request sentRequest;
    final service = LobbyService(
      serverUrl: 'https://dourada.example.workers.dev',
      client: MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'tableNumber': '3',
            'playerToken': 'token-da-cadeira',
            'websocketUrl': 'wss://dourada.example/connect',
            'seatIndex': 0,
            'phase': 'waiting',
            'seats': List<Object?>.filled(6, null),
          }),
          201,
        );
      }),
    );

    await service.joinTable(
      3,
      firebaseIdToken: 'firebase-id-token',
      playerName: 'Maria',
    );

    final body = jsonDecode(sentRequest.body) as Map<String, dynamic>;
    expect(body['firebaseIdToken'], 'firebase-id-token');
    expect(body['playerName'], 'Maria');
    service.dispose();
  });

  test('decodifica as votações enviadas pela mesa', () {
    final entry = TableEntry.fromJson(
      'https://dourada.example.workers.dev',
      {
        'tableNumber': '2',
        'playerToken': 'token',
        'websocketUrl': 'wss://dourada.example/connect',
        'seatIndex': 2,
        'phase': 'waiting',
        'seats': List<Object?>.filled(6, null),
        'fillBotsVotingVersion': 2,
        'challengeVotingVersion': 1,
        'waitingStartAt': null,
        'fillBotsVote': {
          'id': 'vote-1',
          'requesterSeatIndex': 0,
          'participantSeatIndexes': [0, 2, 4],
          'votes': [true, null, null, null, false, null],
          'shownAt': [100, null, null, null, 120, null],
          'expiresAt': 123456789,
        },
        'challengeVote': {
          'id': 'challenge-1',
          'targetTeam': 0,
          'requestedValue': 3,
          'challengerPlayer': 1,
          'expiresAt': 223456789,
          'participantSeatIndexes': [0, 2, 4],
          'votes': [null, null, 'fold', null, null, null],
        },
      },
    );

    expect(entry.fillBotsVotingVersion, 2);
    expect(entry.challengeVotingVersion, 1);
    expect(entry.fillBotsVote?.id, 'vote-1');
    expect(entry.fillBotsVote?.requesterSeatIndex, 0);
    expect(entry.fillBotsVote?.participantSeatIndexes, [0, 2, 4]);
    expect(entry.fillBotsVote?.voteFor(0), isTrue);
    expect(entry.fillBotsVote?.voteFor(2), isNull);
    expect(entry.fillBotsVote?.voteFor(4), isFalse);
    expect(
      entry.fillBotsVote?.shownAtFor(0),
      DateTime.fromMillisecondsSinceEpoch(100),
    );
    expect(entry.fillBotsVote?.shownAtFor(2), isNull);
    expect(
      entry.fillBotsVote?.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(123456789),
    );
    expect(entry.challengeVote?.id, 'challenge-1');
    expect(entry.challengeVote?.participantSeatIndexes, [0, 2, 4]);
    expect(
      entry.challengeVote?.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(223456789),
    );
    expect(entry.challengeVote?.voteFor(0), isNull);
    expect(entry.challengeVote?.voteFor(2), ChallengeVoteChoice.fold);
  });

  test('usa nome e foto do perfil na mesa local', () async {
    final service = LobbyService(serverUrl: '');

    final entry = await service.joinTable(
      1,
      playerName: 'Maria',
      playerPhotoUrl: 'https://example.com/maria.jpg',
    );

    expect(entry.seats.first?.name, 'Maria');
    expect(entry.seats.first?.photoUrl, 'https://example.com/maria.jpg');
    final botPhotos = entry.seats
        .skip(1)
        .map((seat) => seat?.photoUrl)
        .whereType<String>()
        .toSet();
    expect(botPhotos, hasLength(5));
    expect(
      botPhotos.every(
        (photo) => RegExp(
          r'^assets/images/avatar/robos/robo_\d{2}\.png$',
        ).hasMatch(photo),
      ),
      isTrue,
    );
    service.dispose();
  });
}
