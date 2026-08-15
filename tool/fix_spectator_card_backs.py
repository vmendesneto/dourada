from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'Trecho não encontrado em {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1))


# Worker: o espectador recebe somente a quantidade de cartas, nunca os valores.
path = 'cloudflare/src/index.ts'
replace_once(
    path,
    '''      spectator: true,
      spectatorCount: this.spectatorCount(),
      phase: table.phase,
''',
    '''      spectator: true,
      spectatorCount: this.spectatorCount(),
      spectatorHandCounts: spectatorHandCounts(table.gameState),
      phase: table.phase,
''',
)
replace_once(
    path,
    '''      spectator: true,
      spectatorCount: this.spectatorCount(),
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
''',
    '''      spectator: true,
      spectatorCount: this.spectatorCount(),
      spectatorHandCounts: spectatorHandCounts(table.gameState),
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
''',
)
replace_once(
    path,
    '''function spectatorGameState(gameState: GameState | null): GameState | null {
  if (gameState === null) return null;
  return {
    ...gameState,
    playerHands: gameState.playerHands.map(() => []),
    hiddenCards: gameState.hiddenCards?.map(() => []),
  };
}

function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
''',
    '''function spectatorGameState(gameState: GameState | null): GameState | null {
  if (gameState === null) return null;
  return {
    ...gameState,
    playerHands: gameState.playerHands.map(() => []),
    hiddenCards: gameState.hiddenCards?.map(() => []),
  };
}

function spectatorHandCounts(gameState: GameState | null): number[] {
  if (gameState === null) return Array<number>(seatCount).fill(0);
  return gameState.playerHands.map((hand) => hand.length);
}

function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
''',
)

# Entrada do espectador.
path = 'lib/online/lobby_service.dart'
replace_once(
    path,
    '''    this.spectator = false,
    this.spectatorCount = 0,
  });
''',
    '''    this.spectator = false,
    this.spectatorCount = 0,
    this.spectatorHandCounts = const [],
  });
''',
)
replace_once(
    path,
    '''  final bool spectator;
  final int spectatorCount;
''',
    '''  final bool spectator;
  final int spectatorCount;
  final List<int> spectatorHandCounts;
''',
)
replace_once(
    path,
    '''        spectator: json['spectator'] as bool? ?? false,
        spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
      );
''',
    '''        spectator: json['spectator'] as bool? ?? false,
        spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
        spectatorHandCounts:
            (json['spectatorHandCounts'] as List<Object?>? ??
                    const <Object?>[])
                .map((value) => value is num ? value.toInt() : 0)
                .toList(growable: false),
      );
''',
)

# Sessão mantém a contagem sincronizada pelo WebSocket.
path = 'lib/online/table_session.dart'
replace_once(
    path,
    '''      spectatorCount = entry!.spectatorCount;
    }
''',
    '''      spectatorCount = entry!.spectatorCount;
      spectatorHandCounts = entry!.spectatorHandCounts;
    }
''',
)
replace_once(
    path,
    '''  int spectatorCount = 0;
  String? _reportedShownFillBotsVoteId;
''',
    '''  int spectatorCount = 0;
  List<int> spectatorHandCounts = const [];
  String? _reportedShownFillBotsVoteId;
''',
)
replace_once(
    path,
    '''  int get missingPlayers => 6 - playerCount;
''',
    '''  int get missingPlayers => 6 - playerCount;
  int spectatorHandCountFor(int playerIndex) =>
      playerIndex >= 0 && playerIndex < spectatorHandCounts.length
          ? spectatorHandCounts[playerIndex]
          : 0;
''',
)
replace_once(
    path,
    '''    spectatorCount = value.spectatorCount;
    _configureSeats();
''',
    '''    spectatorCount = value.spectatorCount;
    spectatorHandCounts = value.spectatorHandCounts;
    _configureSeats();
''',
)
replace_once(
    path,
    '''    spectatorCount = (payload['spectatorCount'] as num?)?.toInt() ?? 0;
    final gameState = payload['gameState'];
''',
    '''    spectatorCount = (payload['spectatorCount'] as num?)?.toInt() ?? 0;
    final rawSpectatorHandCounts = payload['spectatorHandCounts'];
    spectatorHandCounts = rawSpectatorHandCounts is List
        ? rawSpectatorHandCounts
            .map((value) => value is num ? value.toInt() : 0)
            .toList(growable: false)
        : const [];
    final gameState = payload['gameState'];
''',
)

# UI: todos os seis jogadores mostram somente os versos das cartas restantes.
path = 'lib/ui/game_page.dart'
replace_once(
    path,
    '''                  spectatorMode: spectator,
''',
    '''                  spectatorMode: spectator,
                  hiddenCardCount: spectator
                      ? tableSession.spectatorHandCountFor(playerIndex)
                      : 0,
''',
)
replace_once(
    path,
    '''    this.spectatorMode = false,
  });
''',
    '''    this.spectatorMode = false,
    this.hiddenCardCount = 0,
  });
''',
)
replace_once(
    path,
    '''  final bool spectatorMode;

  @override
''',
    '''  final bool spectatorMode;
  final int hiddenCardCount;

  @override
''',
)
replace_once(
    path,
    '''          if (!spectatorMode && (!compact || reveal)) ...[
            const SizedBox(height: 4),
            Row(
              key: reveal ? ValueKey('cartas-parceiro-$playerIndex') : null,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final card in player.hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: reveal
                        ? _CardFace(card: card, width: 28, height: 40)
                        : const _CardBack(width: 22, height: 32),
                  ),
              ],
            ),
          ],
''',
    '''          if (spectatorMode && hiddenCardCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              key: ValueKey('cartas-espectador-$playerIndex'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < hiddenCardCount; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _CardBack(
                      width: compact ? 18 : 22,
                      height: compact ? 26 : 32,
                    ),
                  ),
              ],
            ),
          ] else if (!spectatorMode && (!compact || reveal)) ...[
            const SizedBox(height: 4),
            Row(
              key: reveal ? ValueKey('cartas-parceiro-$playerIndex') : null,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final card in player.hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: reveal
                        ? _CardFace(card: card, width: 28, height: 40)
                        : const _CardBack(width: 22, height: 32),
                  ),
              ],
            ),
          ],
''',
)

# Teste da resposta inicial do modo espectador.
path = 'test/lobby_service_test.dart'
replace_once(
    path,
    '''            'spectatorCount': 3,
            'seats': List<Object?>.filled(6, null),
''',
    '''            'spectatorCount': 3,
            'spectatorHandCounts': [3, 2, 1, 3, 2, 1],
            'seats': List<Object?>.filled(6, null),
''',
)
replace_once(
    path,
    '''    expect(entry.spectatorCount, 3);
    expect(entry.phase, LobbyTablePhase.playing);
''',
    '''    expect(entry.spectatorCount, 3);
    expect(entry.spectatorHandCounts, [3, 2, 1, 3, 2, 1]);
    expect(entry.phase, LobbyTablePhase.playing);
''',
)

print('Correção dos versos de carta aplicada com sucesso.')
