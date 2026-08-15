from pathlib import Path


def replace_once(path: str, old: str, new: str) -> bool:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return False
    if old not in text:
        raise SystemExit(f"Trecho esperado não encontrado em {path}")
    file.write_text(text.replace(old, new, 1))
    return True


changed = False

changed |= replace_once(
    "lib/game/douradinha_game.dart",
    """    statusMessage = 'Seu trio decidiu jogar a mão de dez.';
    _addHistory(statusMessage);
    notifyListeners();
""",
    """    statusMessage = 'Seu trio decidiu jogar a mão de dez.';
    challengeNotice = statusMessage;
    challengeNoticeAccepted = true;
    _addHistory(statusMessage);
    notifyListeners();
""",
)

changed |= replace_once(
    "lib/game/douradinha_game.dart",
    """    _tenDecisionMade[humanTeam] = true;
    _finishHand(
      1 - humanTeam,
      points: 1,
      reason: 'Seu trio correu na mão de dez.',
    );
""",
    """    _tenDecisionMade[humanTeam] = true;
    const message = 'Seu trio correu na mão de dez.';
    challengeNotice = message;
    challengeNoticeAccepted = false;
    _finishHand(
      1 - humanTeam,
      points: 1,
      reason: message,
    );
""",
)

changed |= replace_once(
    "lib/game/douradinha_game.dart",
    """    if (confidence < 19 && _random.nextDouble() < .65) {
      _finishHand(
        humanTeam,
        points: 1,
        reason: 'O trio adversário correu na mão de dez.',
      );
      return;
    }
    statusMessage = 'O trio adversário decidiu jogar a mão de dez.';
    _addHistory(statusMessage);
    notifyListeners();
""",
    """    if (confidence < 19 && _random.nextDouble() < .65) {
      const message = 'O trio adversário correu na mão de dez.';
      challengeNotice = message;
      challengeNoticeAccepted = false;
      _finishHand(
        humanTeam,
        points: 1,
        reason: message,
      );
      return;
    }
    statusMessage = 'O trio adversário decidiu jogar a mão de dez.';
    challengeNotice = statusMessage;
    challengeNoticeAccepted = true;
    _addHistory(statusMessage);
    notifyListeners();
""",
)

changed |= replace_once(
    "test/douradinha_game_test.dart",
    """      game.currentPlayerIndex = game.humanPlayerIndex;
      game.trickLeaderIndex = game.humanPlayerIndex;
      game.scores[game.humanTeam] = 10;
      game.chooseToPlayTenHand();
      final card = game.players[game.humanPlayerIndex].hand.first;

      expect(game.isHumanTurn, isTrue);
""",
    """      game.scores[game.humanTeam] = 10;
      game.phase = MatchPhase.handFinished;
      game.startNextHand();
      game.currentPlayerIndex = game.humanPlayerIndex;
      game.trickLeaderIndex = game.humanPlayerIndex;
      game.chooseToPlayTenHand();
      final card = game.players[game.humanPlayerIndex].hand.first;

      expect(game.challengeNoticeAccepted, isTrue);
      expect(game.challengeNotice, contains('decidiu jogar a mão de dez'));
      game.clearChallengeNotice();
      expect(game.isHumanTurn, isTrue);
""",
)

changed |= replace_once(
    "test/douradinha_game_test.dart",
    """      game.foldHumanTenHand();

      expect(game.phase, MatchPhase.handFinished);
      expect(game.scores[1], 2);
""",
    """      game.foldHumanTenHand();

      expect(game.challengeNoticeAccepted, isFalse);
      expect(game.challengeNotice, contains('correu na mão de dez'));
      expect(game.phase, MatchPhase.handFinished);
      expect(game.scores[1], 2);
""",
)

changed |= replace_once(
    "test/douradinha_game_test.dart",
    """      game.chooseToPlayTenHand();
      var safety = 0;
""",
    """      game.chooseToPlayTenHand();
      expect(game.challengeNoticeAccepted, isTrue);
      expect(game.challengeNotice, contains('decidiu jogar a mão de dez'));
      game.clearChallengeNotice();
      var safety = 0;
""",
)

changed |= replace_once(
    "test/douradinha_game_test.dart",
    """      expect(game.botTenDecisionPending, isFalse);
      expect(game.canHumanSeePartnerCardsInTenHand, isFalse);
""",
    """      expect(game.botTenDecisionPending, isFalse);
      expect(game.challengeNotice, isNull);
      expect(game.canHumanSeePartnerCardsInTenHand, isFalse);
""",
)

changed |= replace_once(
    "cloudflare/src/game.ts",
    """  const tenTeam = pendingTenTeam(game);
  if (tenTeam !== null) {
    game.tenDecisionMade[tenTeam] = true;
    setStatus(
      game,
      `${teamAction(game, tenTeam, \"decidimos\", \"decidiram\")} jogar a mão de dez.`,
    );
    return { state: game, nextDelayMs: 650 };
  }
""",
    """  const tenTeam = pendingTenTeam(game);
  if (tenTeam !== null) {
    game.tenDecisionMade[tenTeam] = true;
    const message =
      `${teamAction(game, tenTeam, \"decidimos\", \"decidiram\")} jogar a mão de dez.`;
    game.challengeNotice = message;
    game.challengeNoticeAccepted = true;
    game.challengeNoticeUntil = Date.now() + challengeNoticeMs;
    setStatus(game, message);
    return { state: game, nextDelayMs: challengeNoticeMs };
  }
""",
)

changed |= replace_once(
    "cloudflare/test/game.test.ts",
    """  betweenPartidasTransitionMs,
  cardStrength,
""",
    """  betweenPartidasTransitionMs,
  cardStrength,
  challengeNoticeMs,
""",
)

changed |= replace_once(
    "cloudflare/test/game.test.ts",
    """  it(\"joga automaticamente pela cadeira humana ausente\", () => {
""",
    """  it(\"mostra a confirmação quando o trio aceita a mão de dez\", () => {
    const game = fixture();
    game.scores[1] = 10;
    game.tenDecisionMade = [true, false];

    const step = advanceBot(game);

    expect(step.state.tenDecisionMade[1]).toBe(true);
    expect(step.state.challengeNoticeAccepted).toBe(true);
    expect(step.state.challengeNotice).toContain(\"decidiram jogar a mão de dez\");
    expect(step.state.challengeNoticeUntil).not.toBeNull();
    expect(step.nextDelayMs).toBe(challengeNoticeMs);
  });

  it(\"não mostra confirmação automática quando está dez a dez\", () => {
    const game = fixture();
    game.scores = [10, 10];
    game.tenDecisionMade = [true, true];

    const step = advanceBot(game);

    expect(step.state.challengeNotice).toBeNull();
  });

  it(\"joga automaticamente pela cadeira humana ausente\", () => {
""",
)

print("Patch aplicado." if changed else "Ajuste já estava aplicado.")
