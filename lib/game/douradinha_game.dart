import 'dart:math';

import 'package:flutter/foundation.dart';

enum ChallengeDecision { accept, raise, fold }

enum MatchPhase { playing, handFinished, gameOver }

@immutable
class PlayingCard {
  const PlayingCard(this.rank, this.suit);

  final String rank;
  final String suit;

  String get code => '$rank$suit';

  String get suitName => switch (suit) {
        'o' => 'Ouros',
        'e' => 'Espadas',
        'c' => 'Copas',
        _ => 'Paus',
      };

  String get rankName => switch (rank) {
        'A' => 'Ás',
        'K' => 'Rei',
        'Q' => 'Dama',
        'J' => 'Valete',
        _ => rank,
      };

  String get name => '$rankName de $suitName';

  String? get nickname => switch (code) {
        'Qo' => 'Douradinha',
        'Jp' => 'Valetinho',
        '2p' => 'Dunginha',
        'Ap' => 'Azinho',
        '5p' => 'Cinquinho',
        '4p' => 'Zap',
        'Ae' => 'Espadilha',
        _ => null,
      };

  bool get isManilha => strength > 10;

  String get displayName => nickname == null ? name : '$name (${nickname!})';

  int get strength => switch (code) {
        'Qo' => 19,
        'Jp' => 18,
        '2p' => 17,
        'Ap' => 16,
        '5p' => 15,
        '4p' => 14,
        '7c' => 13,
        'Ae' => 12,
        '7o' => 11,
        _ => switch (rank) {
            '3' => 10,
            '2' => 9,
            'A' => 8,
            'K' => 7,
            'J' => 6,
            'Q' => 5,
            '7' => 4,
            '6' => 3,
            '5' => 2,
            _ => 1,
          },
      };

  static List<PlayingCard> fullDeck() {
    const ranks = ['4', '5', '6', '7', 'Q', 'J', 'K', 'A', '2', '3'];
    const suits = ['o', 'e', 'c', 'p'];
    return [
      for (final rank in ranks)
        for (final suit in suits) PlayingCard(rank, suit),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);
}

class PlayerSeat {
  PlayerSeat({
    required this.id,
    required this.name,
    required this.team,
    required this.isHuman,
  });

  final int id;
  final String name;
  final int team;
  final bool isHuman;
  final List<PlayingCard> hand = [];
}

@immutable
class PlayedCard {
  const PlayedCard({required this.playerIndex, required this.card});

  final int playerIndex;
  final PlayingCard card;
}

@immutable
class Challenge {
  const Challenge({
    required this.challengerTeam,
    required this.targetTeam,
    required this.requestedValue,
    required this.responderPlayer,
  });

  final int challengerTeam;
  final int targetTeam;
  final int requestedValue;
  final int responderPlayer;
}

class DouradinhaGame extends ChangeNotifier {
  static const handResultDisplayDuration = Duration(seconds: 5);
  static const challengeNoticeDuration = Duration(seconds: 2);

  DouradinhaGame({Random? random}) : _random = random ?? Random() {
    players = List.generate(
      6,
      (index) => PlayerSeat(
        id: index,
        name: index == 0 ? 'Você' : 'Robô $index',
        team: index.isEven ? 0 : 1,
        isHuman: index == 0,
      ),
    );
    restart();
  }

  final Random _random;
  late final List<PlayerSeat> players;
  final List<int> scores = [0, 0];
  final List<PlayedCard> currentTrick = [];
  final List<PlayedCard> playedCards = [];
  final List<int?> trickWinners = [];
  final List<String> history = [];
  final List<bool> _tenDecisionMade = [true, true];
  final List<bool> _botChallengeConsideredThisTrick = [false, false];
  final List<int> _automaticTimeouts = List.filled(6, 0);

  int dealerIndex = 5;
  int trickLeaderIndex = 0;
  int currentPlayerIndex = 0;
  int handValue = 1;
  int? nextTrickLeader;
  int? matchWinner;
  int? lastChallengeTeam;
  int? lastHandWinner;
  int lastHandPoints = 0;
  int lastCompletedHandNumber = 0;
  int? lastCompletedHandWinnerTeam;
  bool awaitingNextTrick = false;
  bool challengeAttemptedThisTurn = false;
  MatchPhase phase = MatchPhase.playing;
  Challenge? pendingChallenge;
  String? challengeNotice;
  bool challengeNoticeAccepted = false;
  String statusMessage = '';

  bool get isHumanTurn =>
      canCurrentPlayerPlayCard &&
      currentPlayerIndex == 0 &&
      !humanTenDecisionPending;

  bool get canCurrentPlayerPlayCard =>
      phase == MatchPhase.playing &&
      !awaitingNextTrick &&
      pendingChallenge == null &&
      challengeNotice == null &&
      !humanTenDecisionPending &&
      !botTenDecisionPending &&
      currentPlayerIndex >= 0;

  bool get isTenHand => scores[0] == 10 || scores[1] == 10;

  bool get humanTenDecisionPending =>
      phase == MatchPhase.playing && scores[0] == 10 && !_tenDecisionMade[0];

  bool get botTenDecisionPending =>
      phase == MatchPhase.playing && scores[1] == 10 && !_tenDecisionMade[1];

  bool get humanMustAnswerChallenge => pendingChallenge?.targetTeam == 0;

  int get displayedHandNumber {
    if ((awaitingNextTrick || phase == MatchPhase.handFinished) &&
        lastCompletedHandNumber > 0) {
      return lastCompletedHandNumber;
    }
    return min(trickWinners.length + 1, 3);
  }

  bool get canHumanChallenge =>
      isHumanTurn &&
      !isTenHand &&
      !challengeAttemptedThisTurn &&
      canTeamRequestChallenge(0) &&
      handValue < 6;

  int? get nextChallengeValue => nextChallengeAfter(handValue);

  static int? nextChallengeAfter(int currentValue) => switch (currentValue) {
        1 => 2,
        2 => 3,
        3 => 4,
        4 => 6,
        _ => null,
      };

  static int spokenValueForPoints(int points) => switch (points) {
        1 => 2,
        2 => 4,
        3 => 6,
        4 => 9,
        6 => 12,
        _ => points * 2,
      };

  static String challengeLabelForPoints(int points) =>
      points == 2 ? 'TRUCO!' : 'VALE ${spokenValueForPoints(points)}!';

  /// O Trio Azul é representado exclusivamente pelo jogador humano nas apostas.
  static bool botCanDecideChallengeForTeam(int team) => team != 0;

  static bool isChallengeTurnForTeam({
    required int team,
    required int? lastChallengeTeam,
    required int handValue,
  }) =>
      handValue < 6 && (lastChallengeTeam == null || lastChallengeTeam != team);

  bool canTeamRequestChallenge(int team) => isChallengeTurnForTeam(
        team: team,
        lastChallengeTeam: lastChallengeTeam,
        handValue: handValue,
      );

  static int timeLimitAfterTimeouts(int timeoutCount) => switch (timeoutCount) {
        0 => 15,
        1 => 12,
        _ => 8,
      };

  static double botProactiveChallengeProbability({
    required int raiseVotes,
    required int acceptVotes,
    required bool tableIsEmpty,
    required int completedTricks,
    required int handValue,
  }) {
    var probability = switch ((raiseVotes, acceptVotes)) {
      (>= 2, _) => .30,
      (1, >= 1) => .18,
      (1, _) => .10,
      (_, >= 2) => .06,
      _ => .02,
    };

    // No escuro, antes de qualquer carta, o trio é mais conservador.
    if (tableIsEmpty) probability *= .60;
    if (completedTricks == 0) probability *= .85;
    if (handValue == 2) probability *= .75;
    if (handValue >= 3) probability *= .55;
    return probability.clamp(.01, .30).toDouble();
  }

  static double botRaiseResponseProbability({
    required int raiseVotes,
    required int acceptVotes,
    required int requestedValue,
  }) {
    if (requestedValue >= 6) return 0;
    var probability = switch ((raiseVotes, acceptVotes)) {
      (>= 2, _) => .26,
      (1, >= 2) => .12,
      _ => 0.0,
    };
    if (requestedValue == 3) probability *= .75;
    if (requestedValue >= 4) probability *= .55;
    return probability;
  }

  int timeLimitSecondsFor(int playerIndex) =>
      timeLimitAfterTimeouts(_automaticTimeouts[playerIndex]);

  int timeoutCountFor(int playerIndex) => _automaticTimeouts[playerIndex];

  String get teamOneLabel => 'Trio Azul';
  String get teamTwoLabel => 'Trio Dourado';

  void restart() {
    scores
      ..clear()
      ..addAll([0, 0]);
    history.clear();
    _automaticTimeouts.fillRange(0, _automaticTimeouts.length, 0);
    dealerIndex = 5;
    matchWinner = null;
    _dealHand(rotateDealer: false);
  }

  void startNextHand() {
    if (phase != MatchPhase.handFinished) return;
    if (matchWinner != null) {
      phase = MatchPhase.gameOver;
      statusMessage =
          '${matchWinner == 0 ? teamOneLabel : teamTwoLabel} venceu a partida!';
      _addHistory(statusMessage);
      notifyListeners();
      return;
    }
    _dealHand(rotateDealer: true);
  }

  void _dealHand({required bool rotateDealer}) {
    if (rotateDealer) dealerIndex = (dealerIndex + 1) % players.length;
    phase = MatchPhase.playing;
    pendingChallenge = null;
    challengeNotice = null;
    challengeNoticeAccepted = false;
    matchWinner = null;
    lastChallengeTeam = null;
    lastHandWinner = null;
    lastHandPoints = 0;
    lastCompletedHandNumber = 0;
    lastCompletedHandWinnerTeam = null;
    currentTrick.clear();
    playedCards.clear();
    trickWinners.clear();
    awaitingNextTrick = false;
    nextTrickLeader = null;
    challengeAttemptedThisTurn = false;
    _botChallengeConsideredThisTrick.fillRange(0, 2, false);

    final deck = PlayingCard.fullDeck()..shuffle(_random);
    for (final player in players) {
      player.hand.clear();
    }
    for (var round = 0; round < 3; round++) {
      for (var offset = 1; offset <= players.length; offset++) {
        final playerIndex = (dealerIndex + offset) % players.length;
        players[playerIndex].hand.add(deck.removeLast());
      }
    }

    trickLeaderIndex = (dealerIndex + 1) % players.length;
    currentPlayerIndex = trickLeaderIndex;
    handValue = isTenHand ? 3 : 1;
    _tenDecisionMade[0] = scores[0] != 10;
    _tenDecisionMade[1] = scores[1] != 10;
    statusMessage = isTenHand
        ? 'Mão de dez: sem desafios, valendo 6.'
        : 'Nova disputa: ${players[currentPlayerIndex].name} começa.';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void chooseToPlayTenHand() {
    if (!humanTenDecisionPending) return;
    _tenDecisionMade[0] = true;
    statusMessage = 'Seu trio decidiu jogar a mão de dez.';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void foldHumanTenHand() {
    if (!humanTenDecisionPending) return;
    _tenDecisionMade[0] = true;
    _finishHand(1, points: 1, reason: 'Seu trio correu na mão de dez.');
  }

  void resolveBotTenHand() {
    if (!botTenDecisionPending) return;
    _tenDecisionMade[1] = true;
    final cards = players
        .where((player) => player.team == 1)
        .expand((player) => player.hand)
        .map((card) => card.strength)
        .toList();
    cards.sort();
    final confidence = cards.reversed.take(3).fold<int>(0, (a, b) => a + b);
    if (confidence < 19 && _random.nextDouble() < .65) {
      _finishHand(0, points: 1, reason: 'O Trio Dourado correu na mão de dez.');
      return;
    }
    statusMessage = 'O Trio Dourado decidiu jogar a mão de dez.';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void playHumanCard(PlayingCard card) {
    if (!isHumanTurn || !players[0].hand.contains(card)) return;
    _playCard(0, card);
  }

  void autoPlayCurrentPlayerOnTimeout() {
    if (!canCurrentPlayerPlayCard) return;
    final playerIndex = currentPlayerIndex;
    final player = players[playerIndex];
    if (player.hand.isEmpty) return;
    _automaticTimeouts[playerIndex]++;
    _addHistory(
      'O tempo de ${player.name} acabou. Uma carta foi jogada automaticamente.',
    );
    _playCard(playerIndex, _chooseBotCard(player));
  }

  void takeBotTurn() {
    if (phase != MatchPhase.playing ||
        awaitingNextTrick ||
        pendingChallenge != null ||
        currentPlayerIndex == 0 ||
        humanTenDecisionPending ||
        botTenDecisionPending) {
      return;
    }

    final player = players[currentPlayerIndex];
    if (_botShouldChallenge(player)) {
      _requestChallenge(player.team, currentPlayerIndex);
      return;
    }
    _playCard(currentPlayerIndex, _chooseBotCard(player));
  }

  PlayingCard _chooseBotCard(PlayerSeat player) {
    final cards = [...player.hand]
      ..sort((a, b) => a.strength.compareTo(b.strength));
    if (currentTrick.isEmpty) {
      if (trickWinners.isNotEmpty && trickWinners.first == player.team) {
        return cards.first;
      }
      if (cards.length >= 2 && _random.nextDouble() < .65) return cards[1];
      return cards.last;
    }

    final topStrength =
        currentTrick.map((play) => play.card.strength).reduce(max);
    final topTeams = currentTrick
        .where((play) => play.card.strength == topStrength)
        .map((play) => players[play.playerIndex].team)
        .toSet();
    if (topTeams.length == 1 && topTeams.single == player.team) {
      return cards.first;
    }
    return cards.firstWhere(
      (card) => card.strength > topStrength,
      orElse: () => cards.first,
    );
  }

  bool _botShouldChallenge(PlayerSeat player) {
    if (!botCanDecideChallengeForTeam(player.team) ||
        !canTeamRequestChallenge(player.team) ||
        isTenHand ||
        challengeAttemptedThisTurn ||
        _botChallengeConsideredThisTrick[player.team] ||
        handValue >= 6) {
      return false;
    }
    if (_currentTrickIsLockedAgainst(player.team)) return false;

    final requested = nextChallengeValue;
    if (requested == null) return false;
    _botChallengeConsideredThisTrick[player.team] = true;
    final votes = _consultBotTeam(player.team, requested);
    final raises =
        votes.where((vote) => vote == ChallengeDecision.raise).length;
    final accepts =
        votes.where((vote) => vote == ChallengeDecision.accept).length;

    // Cada parceiro informa somente se ajuda, aumenta ou corre. A mão exata
    // nunca é compartilhada. Um pedido forte pode convencer o trio sozinho;
    // sinais de apoio dos demais tornam o desafio mais provável.
    final challengeChance = botProactiveChallengeProbability(
      raiseVotes: raises,
      acceptVotes: accepts,
      tableIsEmpty: currentTrick.isEmpty,
      completedTricks: trickWinners.length,
      handValue: handValue,
    );
    return _random.nextDouble() < challengeChance;
  }

  List<ChallengeDecision> _consultBotTeam(int team, int requestedValue) =>
      players
          .where((player) => player.team == team)
          .map((player) => _botChallengeVote(player, requestedValue))
          .toList(growable: false);

  ChallengeDecision _botChallengeVote(
    PlayerSeat player,
    int requestedValue,
  ) {
    if (_currentTrickIsLockedAgainst(player.team)) {
      return ChallengeDecision.fold;
    }

    final confidence = _botStatisticalConfidence(player);
    final required = switch (requestedValue) {
      2 => .40,
      3 => .49,
      4 => .58,
      _ => .68,
    };
    if (confidence < required) return ChallengeDecision.fold;
    if (requestedValue < 6 && confidence >= required + .17) {
      return ChallengeDecision.raise;
    }
    return ChallengeDecision.accept;
  }

  double _botStatisticalConfidence(PlayerSeat player) {
    final strengths = player.hand.map((card) => card.strength).toList()..sort();
    final best = strengths.isEmpty ? 1 : strengths.last;
    final average = strengths.isEmpty
        ? 1.0
        : strengths.fold<int>(0, (sum, value) => sum + value) /
            strengths.length;

    // O robô conhece sua própria mão e todas as cartas já abertas na mesa.
    // As cartas ainda escondidas são tratadas apenas como possibilidades.
    final knownCodes = <String>{
      ...playedCards.map((play) => play.card.code),
      ...player.hand.map((card) => card.code),
    };
    final unseen = PlayingCard.fullDeck()
        .where((card) => !knownCodes.contains(card.code))
        .toList();
    final strongerUnseen = unseen.where((card) => card.strength > best).length;
    final safety = unseen.isEmpty ? 1.0 : 1 - strongerUnseen / unseen.length;

    var confidence = .08 +
        ((best - 1) / 18) * .48 +
        ((average - 1) / 18) * .22 +
        safety * .14;

    if (currentTrick.isNotEmpty) {
      final topStrength =
          currentTrick.map((play) => play.card.strength).reduce(max);
      final topTeams = currentTrick
          .where((play) => play.card.strength == topStrength)
          .map((play) => players[play.playerIndex].team)
          .toSet();
      if (topTeams.length == 1 && topTeams.single == player.team) {
        confidence += .13;
      } else if (topTeams.length == 1) {
        confidence += best > topStrength ? .10 : -.18;
      }
    }

    final teamWins =
        trickWinners.where((winner) => winner == player.team).length;
    final opponentWins =
        trickWinners.where((winner) => winner == 1 - player.team).length;
    confidence += (teamWins - opponentWins) * .08;

    // Na terceira mão, perder a carta mais alta é especialmente perigoso,
    // pois o desempate pode ser definido pela primeira mão.
    if (trickWinners.length == 2 &&
        currentTrick.isNotEmpty &&
        !_teamCurrentlyLeadsTrick(player.team)) {
      confidence -= .10;
    }
    return confidence.clamp(0.0, 1.0);
  }

  bool _teamCurrentlyLeadsTrick(int team) {
    if (currentTrick.isEmpty) return false;
    final topStrength =
        currentTrick.map((play) => play.card.strength).reduce(max);
    final topTeams = currentTrick
        .where((play) => play.card.strength == topStrength)
        .map((play) => players[play.playerIndex].team)
        .toSet();
    return topTeams.length == 1 && topTeams.single == team;
  }

  bool _currentTrickIsLockedAgainst(int team) {
    if (currentTrick.isEmpty) return false;
    final topStrength =
        currentTrick.map((play) => play.card.strength).reduce(max);
    final publicCodes = <String>{
      ...playedCards.map((play) => play.card.code),
      ...currentTrick.map((play) => play.card.code),
    };
    final aStrongerCardCanStillAppear = PlayingCard.fullDeck().any(
      (card) => !publicCodes.contains(card.code) && card.strength > topStrength,
    );
    if (aStrongerCardCanStillAppear) return false;

    final topTeams = currentTrick
        .where((play) => play.card.strength == topStrength)
        .map((play) => players[play.playerIndex].team)
        .toSet();
    final provisionalWinner = topTeams.length == 1 ? topTeams.single : null;
    final disputeWinner = resolveDisputeWinner([
      ...trickWinners,
      provisionalWinner,
    ]);
    return disputeWinner != null && disputeWinner != team;
  }

  void requestHumanChallenge() {
    if (!canHumanChallenge) return;
    _requestChallenge(0, 0);
  }

  void _requestChallenge(int team, int playerIndex) {
    final requested = nextChallengeValue;
    if (requested == null || !canTeamRequestChallenge(team)) return;
    challengeAttemptedThisTurn = true;
    lastChallengeTeam = team;
    pendingChallenge = Challenge(
      challengerTeam: team,
      targetTeam: 1 - team,
      requestedValue: requested,
      responderPlayer: _nextPlayerOnTeam(playerIndex, 1 - team),
    );
    final call = challengeLabelForPoints(requested);
    statusMessage = playerIndex == 0
        ? '${players[playerIndex].name} pediu $call'
        : '${players[playerIndex].name} consultou os parceiros e pediu $call';
    _addHistory(statusMessage);
    notifyListeners();
  }

  int _nextPlayerOnTeam(int from, int team) {
    for (var offset = 1; offset < players.length; offset++) {
      final candidate = (from + offset) % players.length;
      if (players[candidate].team == team) return candidate;
    }
    return 0;
  }

  void acceptHumanChallenge() {
    if (!humanMustAnswerChallenge) return;
    _acceptChallenge(
      'Seu trio aceitou: agora vale ${spokenValueForPoints(pendingChallenge!.requestedValue)}.',
    );
  }

  void foldHumanChallenge() {
    if (!humanMustAnswerChallenge) return;
    final challenge = pendingChallenge!;
    _finishHand(
      challenge.challengerTeam,
      points: handValue,
      reason: 'Seu trio correu do desafio.',
    );
  }

  void raiseHumanChallenge() {
    if (!humanMustAnswerChallenge || pendingChallenge!.requestedValue >= 6) {
      return;
    }
    _raiseChallenge(0, 0);
  }

  void resolveBotChallenge() {
    final challenge = pendingChallenge;
    if (challenge == null || challenge.targetTeam == 0) return;
    _botChallengeConsideredThisTrick[1] = true;
    final votes = _consultBotTeam(1, challenge.requestedValue);
    final folds = votes.where((vote) => vote == ChallengeDecision.fold).length;
    final raises =
        votes.where((vote) => vote == ChallengeDecision.raise).length;
    final accepts =
        votes.where((vote) => vote == ChallengeDecision.accept).length;

    // O trio decide pelos sinais: um parceiro muito confiante evita uma fuga
    // precipitada, mas o aumento exige apoio de pelo menos dois robôs.
    if (folds >= 2 && raises == 0) {
      challengeNotice = 'O Trio Dourado conversou e correu do desafio.';
      challengeNoticeAccepted = false;
      _finishHand(
        challenge.challengerTeam,
        points: handValue,
        reason: 'O Trio Dourado conversou e correu do desafio.',
      );
    } else if (_random.nextDouble() <
        botRaiseResponseProbability(
          raiseVotes: raises,
          acceptVotes: accepts,
          requestedValue: challenge.requestedValue,
        )) {
      _raiseChallenge(1, challenge.responderPlayer);
    } else {
      _acceptChallenge(
        'O Trio Dourado conversou e aceitou: vale ${spokenValueForPoints(challenge.requestedValue)}.',
        showNotice: true,
      );
    }
  }

  void _acceptChallenge(String message, {bool showNotice = false}) {
    final challenge = pendingChallenge!;
    handValue = challenge.requestedValue;
    pendingChallenge = null;
    if (showNotice) {
      challengeNotice = message;
      challengeNoticeAccepted = true;
    }
    statusMessage = message;
    _addHistory(message);
    notifyListeners();
  }

  void clearChallengeNotice() {
    if (challengeNotice == null) return;
    challengeNotice = null;
    challengeNoticeAccepted = false;
    notifyListeners();
  }

  void _raiseChallenge(int raisingTeam, int playerIndex) {
    final challenge = pendingChallenge!;
    handValue = challenge.requestedValue;
    final requested = nextChallengeValue!;
    lastChallengeTeam = raisingTeam;
    pendingChallenge = Challenge(
      challengerTeam: raisingTeam,
      targetTeam: 1 - raisingTeam,
      requestedValue: requested,
      responderPlayer: _nextPlayerOnTeam(playerIndex, 1 - raisingTeam),
    );
    statusMessage = playerIndex == 0
        ? '${players[playerIndex].name} pediu ${challengeLabelForPoints(requested)}'
        : '${players[playerIndex].name} consultou os parceiros e pediu ${challengeLabelForPoints(requested)}';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void _playCard(int playerIndex, PlayingCard card) {
    final player = players[playerIndex];
    player.hand.remove(card);
    final play = PlayedCard(playerIndex: playerIndex, card: card);
    currentTrick.add(play);
    playedCards.add(play);
    statusMessage = '${player.name} jogou ${card.displayName}.';
    _addHistory(statusMessage);

    if (currentTrick.length == players.length) {
      _finishTrick();
      return;
    }
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    challengeAttemptedThisTurn = false;
    notifyListeners();
  }

  void _finishTrick() {
    final winner = resolveTrickWinner(currentTrick, players);
    trickWinners.add(winner?.team);
    lastCompletedHandNumber = trickWinners.length;
    lastCompletedHandWinnerTeam = winner?.team;
    if (winner == null) {
      nextTrickLeader = nextHandLeader(
        currentLeader: trickLeaderIndex,
        winningPlayer: null,
      );
      statusMessage = 'A ${trickWinners.length}ª mão empatou.';
    } else {
      nextTrickLeader = nextHandLeader(
        currentLeader: trickLeaderIndex,
        winningPlayer: winner.id,
      );
      statusMessage =
          '${winner.team == 0 ? teamOneLabel : teamTwoLabel} venceu a ${trickWinners.length}ª mão.';
    }
    _addHistory(statusMessage);

    final disputeWinner = resolveDisputeWinner(trickWinners);
    if (disputeWinner != null) {
      _finishHand(disputeWinner, points: handValue, reason: statusMessage);
      return;
    }
    if (trickWinners.length == 3) {
      _finishDisputeWithoutPoints();
      return;
    }
    awaitingNextTrick = true;
    currentPlayerIndex = -1;
    notifyListeners();
  }

  void beginNextTrick() {
    if (!awaitingNextTrick || phase != MatchPhase.playing) return;
    currentTrick.clear();
    awaitingNextTrick = false;
    lastCompletedHandNumber = 0;
    lastCompletedHandWinnerTeam = null;
    trickLeaderIndex = nextTrickLeader!;
    currentPlayerIndex = trickLeaderIndex;
    challengeAttemptedThisTurn = false;
    _botChallengeConsideredThisTrick.fillRange(0, 2, false);
    statusMessage = '${players[currentPlayerIndex].name} começa a próxima mão.';
    notifyListeners();
  }

  void _finishHand(int winningTeam,
      {required int points, required String reason}) {
    pendingChallenge = null;
    awaitingNextTrick = false;
    scores[winningTeam] += points;
    lastHandWinner = winningTeam;
    lastHandPoints = points;
    statusMessage =
        '$reason ${winningTeam == 0 ? teamOneLabel : teamTwoLabel} ganhou $points ${points == 1 ? 'tento' : 'tentos'}.';
    _addHistory(statusMessage);
    if (scores[winningTeam] >= 12) {
      matchWinner = winningTeam;
    }
    phase = MatchPhase.handFinished;
    notifyListeners();
  }

  void _finishDisputeWithoutPoints() {
    pendingChallenge = null;
    awaitingNextTrick = false;
    lastHandWinner = null;
    lastHandPoints = 0;
    statusMessage = 'As três mãos empataram. Nenhum trio ganhou tentos.';
    _addHistory(statusMessage);
    phase = MatchPhase.handFinished;
    notifyListeners();
  }

  void _addHistory(String entry) {
    history.insert(0, entry);
    if (history.length > 30) history.removeLast();
  }

  static PlayerSeat? resolveTrickWinner(
    List<PlayedCard> plays,
    List<PlayerSeat> seats,
  ) {
    if (plays.isEmpty) return null;
    final maxStrength = plays.map((play) => play.card.strength).reduce(max);
    final strongest =
        plays.where((play) => play.card.strength == maxStrength).toList();
    final teams = strongest.map((play) => seats[play.playerIndex].team).toSet();
    if (teams.length > 1) return null;
    return seats[strongest.first.playerIndex];
  }

  static int nextHandLeader({
    required int currentLeader,
    required int? winningPlayer,
  }) =>
      winningPlayer ?? currentLeader;

  static int? resolveDisputeWinner(List<int?> results) {
    if (results.length < 2) return null;
    final first = results[0];
    final second = results[1];
    if (first == null && second != null) return second;
    if (first != null && (second == first || second == null)) return first;
    if (results.length < 3) return null;
    final third = results[2];
    if (third != null) return third;
    if (first != null) return first;
    if (second != null) return second;
    return null;
  }
}
