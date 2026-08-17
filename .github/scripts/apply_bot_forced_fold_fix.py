from pathlib import Path
import re


def sub_once(path: str, pattern: str, replacement: str) -> None:
    file = Path(path)
    text = file.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: trecho não encontrado")
    file.write_text(updated)


def insert_once(path: str, marker: str, addition: str) -> None:
    file = Path(path)
    text = file.read_text()
    if text.count(marker) != 1:
        raise SystemExit(f"{path}: marcador não encontrado ou duplicado")
    file.write_text(text.replace(marker, addition + marker, 1))


# Flutter: em vez de procurar cartas maiores no baralho inteiro, considera
# somente as cartas dos integrantes do trio que ainda não jogaram nesta mão.
dart_lock = '''  bool _currentTrickIsLockedAgainst(int team) {
    final visibleTrick = currentTrick.where((play) => !play.hidden).toList();
    if (visibleTrick.isEmpty) return false;

    final playersWhoAlreadyPlayed =
        currentTrick.map((play) => play.playerIndex).toSet();
    final remainingTeamCards = <({int playerIndex, PlayingCard card})>[
      for (final player in players)
        if (player.team == team &&
            !playersWhoAlreadyPlayed.contains(player.id))
          for (final card in player.hand)
            (playerIndex: player.id, card: card),
    ];

    bool disputeIsLostWith(List<PlayedCard> trick) {
      final provisionalWinner = resolveTrickWinner(trick, players)?.team;
      final disputeWinner = resolveDisputeWinner([
        ...trickWinners,
        provisionalWinner,
      ]);
      return disputeWinner != null && disputeWinner != team;
    }

    if (remainingTeamCards.isEmpty) {
      return disputeIsLostWith(currentTrick);
    }

    // Só é derrota matemática quando nenhuma carta que este trio ainda pode
    // realmente jogar evita que a disputa seja encerrada contra ele.
    for (final candidate in remainingTeamCards) {
      final simulatedTrick = [
        ...currentTrick,
        PlayedCard(
          playerIndex: candidate.playerIndex,
          card: candidate.card,
        ),
      ];
      if (!disputeIsLostWith(simulatedTrick)) return false;
    }
    return true;
  }'''
sub_once(
    'lib/game/douradinha_game.dart',
    r'  bool _currentTrickIsLockedAgainst\(int team\) \{.*?\n  \}(?=\n\n  void requestHumanChallenge\(\))',
    dart_lock,
)

# Derrota matemática tem precedência sobre a regra de não correr quando
# entregar os tentos atuais encerraria a partida: aceitar não pode salvar a mão.
dart = Path('lib/game/douradinha_game.dart')
text = dart.read_text()
pattern = re.compile(
    r'(  void resolveBotChallenge\(\) \{.*?'
    r'    final botTeam = 1 - humanTeam;\n'
    r'    _botChallengeConsideredThisTrick\[botTeam\] = true;\n)',
    re.S,
)
match = pattern.search(text)
if match is None:
    raise SystemExit('Dart: resolveBotChallenge não encontrado')
early_fold = '''
    if (_currentTrickIsLockedAgainst(botTeam)) {
      const message = 'O trio adversário conversou e correu do desafio.';
      challengeNotice = message;
      challengeNoticeAccepted = false;
      _finishHand(
        challenge.challengerTeam,
        points: handValue,
        reason: message,
      );
      return;
    }
'''
text = text[:match.end()] + early_fold + text[match.end():]
dart.write_text(text)

# Regressões locais: perde obrigatoriamente se nenhuma carta restante salva;
# mantém decisão normal quando algum integrante ainda consegue superar a mesa.
dart_tests = '''    test('trio de robôs corre quando a disputa já está matematicamente perdida', () {
      final game = DouradinhaGame(random: Random(43));
      game.currentPlayerIndex = game.humanPlayerIndex;
      game.trickLeaderIndex = 2;
      game.trickWinners.add(0);
      const leadingPlay = PlayedCard(
        playerIndex: 2,
        card: PlayingCard('J', 'p'),
      );
      game.currentTrick.add(leadingPlay);
      game.playedCards.add(leadingPlay);
      final botCards = <int, List<PlayingCard>>{
        1: const [PlayingCard('2', 'p')],
        3: const [PlayingCard('A', 'p')],
        5: const [PlayingCard('5', 'p')],
      };
      for (final entry in botCards.entries) {
        game.players[entry.key].hand
          ..clear()
          ..addAll(entry.value);
      }

      game.requestHumanChallenge();
      game.resolveBotChallenge();

      expect(game.phase, MatchPhase.handFinished);
      expect(game.lastHandWinner, 0);
      expect(game.pendingChallenge, isNull);
      expect(game.challengeNoticeAccepted, isFalse);
      expect(game.challengeNotice, contains('correu'));
    });

    test('trio não é forçado a correr se ainda consegue superar a mesa', () {
      final game = DouradinhaGame(random: Random(47));
      game.currentPlayerIndex = game.humanPlayerIndex;
      game.trickLeaderIndex = 2;
      game.trickWinners.add(0);
      const leadingPlay = PlayedCard(
        playerIndex: 2,
        card: PlayingCard('J', 'p'),
      );
      game.currentTrick.add(leadingPlay);
      game.playedCards.add(leadingPlay);
      final botCards = <int, List<PlayingCard>>{
        1: const [PlayingCard('2', 'p')],
        3: const [PlayingCard('Q', 'o')],
        5: const [PlayingCard('A', 'p')],
      };
      for (final entry in botCards.entries) {
        game.players[entry.key].hand
          ..clear()
          ..addAll(entry.value);
      }

      game.requestHumanChallenge();
      game.resolveBotChallenge();

      expect(game.phase, MatchPhase.playing);
      expect(game.lastHandWinner, isNull);
      expect(game.scores, [0, 0]);
    });

'''
insert_once(
    'test/douradinha_game_test.dart',
    "    test('trio de robôs conversa e corre quando todos estão fracos', () {\n",
    dart_tests,
)

# Worker: o bot/substituto também deve correr automaticamente se o trio alvo
# já não possui nenhuma carta jogável capaz de evitar a derrota da disputa.
sub_once(
    'cloudflare/src/game.ts',
    r'  if \(game\.pendingChallenge !== null\) \{\s*'
    r'acceptPendingChallenge\(game\);\s*'
    r'return \{ state: game, nextDelayMs: 650 \};\s*'
    r'\}',
    '''  if (game.pendingChallenge !== null) {
    if (
      currentTrickIsLockedAgainst(game, game.pendingChallenge.targetTeam)
    ) {
      foldPendingChallenge(game);
    } else {
      acceptPendingChallenge(game);
    }
    return { state: game, nextDelayMs: 650 };
  }''',
)

ts_helper = '''export function currentTrickIsLockedAgainst(
  game: GameState,
  team: number,
): boolean {
  const visibleTrick = game.currentTrick.filter((play) => !play.hidden);
  if (visibleTrick.length === 0) return false;

  const playersWhoAlreadyPlayed = new Set(
    game.currentTrick.map((play) => play.playerIndex),
  );
  const remainingTeamCards = game.playerHands.flatMap((hand, playerIndex) =>
    playerIndex % 2 === team && !playersWhoAlreadyPlayed.has(playerIndex)
      ? hand.map((card) => ({ playerIndex, card }))
      : [],
  );

  const disputeIsLostWith = (trick: PlayedCardState[]): boolean => {
    const provisionalWinner = resolveTrickWinner(trick);
    const provisionalTeam =
      provisionalWinner === null ? null : provisionalWinner % 2;
    const disputeWinner = resolveDisputeWinner([
      ...game.trickWinners,
      provisionalTeam,
    ]);
    return disputeWinner !== null && disputeWinner !== team;
  };

  if (remainingTeamCards.length === 0) {
    return disputeIsLostWith(game.currentTrick);
  }

  return remainingTeamCards.every(({ playerIndex, card }) =>
    disputeIsLostWith([
      ...game.currentTrick,
      { playerIndex, card },
    ]),
  );
}

'''
insert_once(
    'cloudflare/src/game.ts',
    'function chooseBotCard(game: GameState, playerIndex: number): string | null {\n',
    ts_helper,
)

worker_tests = '''  it("robô substituto corre quando a disputa já está matematicamente perdida", () => {
    const game = fixture();
    game.trickWinners = [0];
    game.currentTrick = [{ playerIndex: 2, card: "Jp" }];
    game.playedCards = [...game.currentTrick];
    game.playerHands = [["4o"], ["2p"], [], ["Ap"], ["5o"], ["5p"]];
    game.pendingChallenge = {
      challengerTeam: 0,
      challengerPlayer: 0,
      targetTeam: 1,
      requestedValue: 2,
      responderPlayer: 1,
    };

    const step = advanceBot(game);

    expect(step.state.phase).toBe("handFinished");
    expect(step.state.lastHandWinner).toBe(0);
    expect(step.state.pendingChallenge).toBeNull();
    expect(step.state.challengeNoticeAccepted).toBe(false);
    expect(step.state.challengeNotice).toContain("correram");
  });

  it("robô substituto pode aceitar quando o trio ainda consegue superar a mesa", () => {
    const game = fixture();
    game.trickWinners = [0];
    game.currentTrick = [{ playerIndex: 2, card: "Jp" }];
    game.playedCards = [...game.currentTrick];
    game.playerHands = [["4o"], ["2p"], [], ["Qo"], ["5o"], ["Ap"]];
    game.pendingChallenge = {
      challengerTeam: 0,
      challengerPlayer: 0,
      targetTeam: 1,
      requestedValue: 2,
      responderPlayer: 1,
    };

    const step = advanceBot(game);

    expect(step.state.phase).toBe("playing");
    expect(step.state.handValue).toBe(2);
    expect(step.state.pendingChallenge).toBeNull();
    expect(step.state.challengeNoticeAccepted).toBe(true);
  });

'''
insert_once(
    'cloudflare/test/game.test.ts',
    '  it("aplica no servidor aceitar, correr e aumentar", () => {\n',
    worker_tests,
)
