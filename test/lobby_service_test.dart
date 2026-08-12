import 'dart:convert';

import 'package:dourada/online/lobby_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
