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
        '2p' => 'Dunguinha',
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

  static PlayingCard fromCode(String code) {
    if (code.length < 2) throw const FormatException('Carta inválida.');
    final card = PlayingCard(
        code.substring(0, code.length - 1), code.substring(code.length - 1));
    if (!fullDeck().contains(card)) {
      throw const FormatException('Carta inválida.');
    }
    return card;
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
    this.photoUrl,
  });

  final int id;
  String name;
  final int team;
  bool isHuman;
  String? photoUrl;
  final List<PlayingCard> hand = [];
  final Set<PlayingCard> hiddenCards = {};
}

@immutable
class PlayedCard {
  const PlayedCard({
    required this.playerIndex,
    required this.card,
    this.hidden = false,
  });

  final int playerIndex;
  final PlayingCard card;
  final bool hidden;
}

@immutable
class Challenge {
  const Challenge({
    required this.challengerTeam,
    required this.challengerPlayer,
    required this.targetTeam,
    required this.requestedValue,
    required this.responderPlayer,
  });

  final int challengerTeam;
  final int challengerPlayer;
  final int targetTeam;
  final int requestedValue;
  final int responderPlayer;
}

class DouradinhaGame extends ChangeNotifier {
  static const handTransitionDuration = Duration(seconds: 2);
  static const partidaStartDelay = Duration(milliseconds: 1500);
  static const betweenPartidasTransitionDuration = Duration(milliseconds: 3500);
  static const challengeNoticeDuration = Duration(seconds: 2);
  static const challengeAnimationDuration = Duration(milliseconds: 2780);
  static const signalDuration = Duration(milliseconds: 350);
  static const defaultSignalEmoji = '🙂';

  DouradinhaGame({Random? random, this.humanPlayerIndex = 0})
      : _random = random ?? Random() {
    players = List.generate(
      6,
      (index) => PlayerSeat(
        id: index,
        name: index == humanPlayerIndex ? 'Você' : 'Robô $index',
        team: index.isEven ? 0 : 1,
        isHuman: index == humanPlayerIndex,
      ),
    );
    restart();
  }

  final Random _random;
  final int humanPlayerIndex;
  late final List<PlayerSeat> players;
  final List<int> scores = [0, 0];
  final List<PlayedCard> currentTrick = [];
  final List<PlayedCard> playedCards = [];
  final List<int?> trickWinners = [];
  final List<String> history = [];
  final List<bool> _tenDecisionMade = [true, true];
  final List<bool> _botChallengeConsideredThisTrick = [false, false];
  final List<int> _automaticTimeouts = List.filled(6, 0);
  final List<String?> _playerSignalEmojis = List.filled(6, null);
  final List<int> _playerSignalExpiresAt = List.filled(6, 0);

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

  int get humanTeam => players[humanPlayerIndex].team;

  void configureSeats(
    List<({String name, bool isHuman, String? photoUrl})?> seats,
  ) {
    if (seats.length != players.length) return;
    for (var index = 0; index < players.length; index++) {
      final seat = seats[index];
      if (seat == null) continue;
      players[index]
        ..name = seat.name
        ..isHuman = seat.isHuman
        ..photoUrl = seat.photoUrl;
    }
  }

  bool get isHumanTurn =>
      canCurrentPlayerPlayCard &&
      currentPlayerIndex == humanPlayerIndex &&
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

  bool get isTenToTen => scores[0] == 10 && scores[1] == 10;

  bool get humanTenDecisionPending =>
      phase == MatchPhase.playing &&
      !isTenToTen &&
      scores[humanTeam] == 10 &&
      !_tenDecisionMade[humanTeam];

  bool get botTenDecisionPending =>
      phase == MatchPhase.playing &&
      !isTenToTen &&
      scores[1 - humanTeam] == 10 &&
      !_tenDecisionMade[1 - humanTeam];

  bool get canHumanSeePartnerCardsInTenHand =>
      humanTenDecisionPending && !isTenToTen;

  bool get humanMustAnswerChallenge =>
      pendingChallenge?.targetTeam == humanTeam;

  int get displayedHandNumber {
    if ((awaitingNextTrick || phase == MatchPhase.handFinished) &&
        lastCompletedHandNumber > 0) {
      return lastCompletedHandNumber;
    }
    return min(trickWinners.length + 1, 3);
  }

  int get footIndex => lastPlayerForLeader(
        leaderIndex: trickLeaderIndex,
        playerCount: players.length,
      );

  static int lastPlayerForLeader({
    required int leaderIndex,
    required int playerCount,
  }) =>
      (leaderIndex + playerCount - 1) % playerCount;

  bool get canHumanChallenge =>
      isHumanTurn &&
      !isTenHand &&
      !challengeAttemptedThisTurn &&
      canTeamRequestChallenge(humanTeam) &&
      handValue < 6;

  int? get nextChallengeValue => nextChallengeAfter(handValue);

  String get challengeButtonLabel {
    if (isTenHand) return 'TRUCO PROIBIDO';
    final nextValue = nextChallengeValue;
    return nextValue == null
        ? 'SEM DESAFIO'
        : challengeLabelForPoints(nextValue);
  }

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

  /// Pontos exibidos no placar de 12, equivalentes às seis pedrinhas reais.
  /// O pedido continua sendo chamado de Vale 9, mas corresponde a quatro
  /// pedrinhas e, portanto, soma oito pontos no placar.
  static int scorePointsForHandValue(int handValue) => switch (handValue) {
        1 => 2,
        2 => 4,
        3 => 6,
        4 => 8,
        6 => 12,
        _ => handValue * 2,
      };

  static String challengeLabelForPoints(int points) =>
      points == 2 ? 'TRUCO!' : 'VALE ${spokenValueForPoints(points)}!';

  static String? challengeGifAssetForPoints(int points) => switch (points) {
        2 => 'assets/gifs/truco.gif',
        3 => 'assets/gifs/vale_6.gif',
        4 => 'assets/gifs/vale_9.gif',
        6 => 'assets/gifs/vale_12.gif',
        _ => null,
      };

  /// Nós somos representados exclusivamente pelo jogador humano nas apostas.
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

  String teamLabel(int team) => team == humanTeam ? 'Nós' : 'Eles';

  String teamWon(int team, String complement) => team == humanTeam
      ? 'Nós vencemos $complement'
      : 'Eles venceram $complement';

  String teamScored(int team, int points) => team == humanTeam
      ? 'Nós marcamos $points pontos.'
      : 'Eles marcaram $points pontos.';

  String get teamOneLabel => teamLabel(0);
  String get teamTwoLabel => teamLabel(1);

  String signalEmojiFor(int playerIndex) {
    if (playerIndex < 0 || playerIndex >= players.length) {
      return defaultSignalEmoji;
    }
    final emoji = _playerSignalEmojis[playerIndex];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (emoji == null || _playerSignalExpiresAt[playerIndex] <= now) {
      return defaultSignalEmoji;
    }
    return emoji;
  }

  Duration? get timeUntilNextSignalExpires {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? nextExpiry;
    for (var index = 0; index < _playerSignalExpiresAt.length; index++) {
      if (_playerSignalEmojis[index] == null) continue;
      final expiry = _playerSignalExpiresAt[index];
      if (expiry <= now) return Duration.zero;
      if (nextExpiry == null || expiry < nextExpiry) nextExpiry = expiry;
    }
    if (nextExpiry == null) return null;
    return Duration(milliseconds: nextExpiry - now);
  }

  void showHumanSignal(String emoji) {
    showPlayerSignal(humanPlayerIndex, emoji);
  }

  void showPlayerSignal(int playerIndex, String emoji) {
    if (playerIndex < 0 || playerIndex >= players.length || emoji.isEmpty) {
      return;
    }
    _playerSignalEmojis[playerIndex] = emoji;
    _playerSignalExpiresAt[playerIndex] =
        DateTime.now().millisecondsSinceEpoch + signalDuration.inMilliseconds;
    notifyListeners();
  }

  void clearExpiredPlayerSignals() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (var index = 0; index < _playerSignalEmojis.length; index++) {
      if (_playerSignalEmojis[index] == null ||
          _playerSignalExpiresAt[index] > now) {
        continue;
      }
      _playerSignalEmojis[index] = null;
      _playerSignalExpiresAt[index] = 0;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Map<String, Object?> toJson() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'version': 1,
      'perspectiveTeam': humanTeam,
      'scores': scores,
      'playerHands': [
        for (final player in players)
          [for (final card in player.hand) card.code],
      ],
      'hiddenCards': [
        for (final player in players)
          [for (final card in player.hiddenCards) card.code],
      ],
      'currentTrick': [
        for (final play in currentTrick) _playedCardToJson(play)
      ],
      'playedCards': [for (final play in playedCards) _playedCardToJson(play)],
      'trickWinners': trickWinners,
      'history': history,
      'tenDecisionMade': _tenDecisionMade,
      'botChallengeConsideredThisTrick': _botChallengeConsideredThisTrick,
      'automaticTimeouts': _automaticTimeouts,
      'playerSignals': [
        for (var index = 0; index < players.length; index++)
          _playerSignalToJson(index, now),
      ],
      'dealerIndex': dealerIndex,
      'trickLeaderIndex': trickLeaderIndex,
      'currentPlayerIndex': currentPlayerIndex,
      'handValue': handValue,
      'nextTrickLeader': nextTrickLeader,
      'matchWinner': matchWinner,
      'lastChallengeTeam': lastChallengeTeam,
      'lastHandWinner': lastHandWinner,
      'lastHandPoints': lastHandPoints,
      'lastCompletedHandNumber': lastCompletedHandNumber,
      'lastCompletedHandWinnerTeam': lastCompletedHandWinnerTeam,
      'awaitingNextTrick': awaitingNextTrick,
      'challengeAttemptedThisTurn': challengeAttemptedThisTurn,
      'phase': phase.name,
      'pendingChallenge': pendingChallenge == null
          ? null
          : {
              'challengerTeam': pendingChallenge!.challengerTeam,
              'challengerPlayer': pendingChallenge!.challengerPlayer,
              'targetTeam': pendingChallenge!.targetTeam,
              'requestedValue': pendingChallenge!.requestedValue,
              'responderPlayer': pendingChallenge!.responderPlayer,
            },
      'challengeNotice': challengeNotice,
      'challengeNoticeAccepted': challengeNoticeAccepted,
      'statusMessage': statusMessage,
    };
  }

  /// Restaura uma partida salva. Se os dados estiverem incompletos ou forem de
  /// outra versão, mantém a nova partida criada pelo construtor.
  bool restoreState(Map<String, dynamic> json) {
    try {
      if (json['version'] != 1) return false;

      final restoredScores = _intList(json['scores'], length: 2);
      final restoredHands = (json['playerHands'] as List<Object?>)
          .map((hand) => (hand as List<Object?>)
              .map((code) => PlayingCard.fromCode(code as String))
              .toList())
          .toList();
      if (restoredHands.length != players.length) return false;
      final restoredHiddenCards = json['hiddenCards'] == null
          ? List<List<PlayingCard>>.generate(players.length, (_) => [])
          : (json['hiddenCards'] as List<Object?>)
              .map((cards) => (cards as List<Object?>)
                  .map((code) => PlayingCard.fromCode(code as String))
                  .toList())
              .toList();
      if (restoredHiddenCards.length != players.length ||
          restoredHiddenCards.any((cards) => cards.length > 1)) {
        return false;
      }

      final restoredCurrentTrick = _playedCardList(json['currentTrick']);
      final restoredPlayedCards = _playedCardList(json['playedCards']);
      if ((restoredScores.contains(10) &&
              restoredCurrentTrick.any((play) => play.hidden)) ||
          [0, 1].any((team) =>
              restoredCurrentTrick
                  .where((play) => play.hidden && play.playerIndex % 2 == team)
                  .length >
              2)) {
        return false;
      }
      final restoredTrickWinners = (json['trickWinners'] as List<Object?>)
          .map((winner) => winner == null ? null : winner as int)
          .toList();
      final sourcePerspective = json['perspectiveTeam'] as int? ?? 0;
      String restoreMessage(String message) => sourcePerspective == humanTeam
          ? message
          : _swapTeamPerspective(message);
      final restoredHistory = (json['history'] as List<Object?>)
          .cast<String>()
          .map(restoreMessage)
          .toList();
      final restoredTenDecisionMade =
          (json['tenDecisionMade'] as List<Object?>).cast<bool>();
      final restoredBotConsidered =
          (json['botChallengeConsideredThisTrick'] as List<Object?>)
              .cast<bool>();
      final restoredTimeouts =
          _intList(json['automaticTimeouts'], length: players.length);
      final restoredSignals =
          _playerSignalList(json['playerSignals'], length: players.length);
      if (restoredTenDecisionMade.length != 2 ||
          restoredBotConsidered.length != 2) {
        return false;
      }

      final restoredPendingChallenge = json['pendingChallenge'] == null
          ? null
          : _challengeFromJson(
              Map<String, dynamic>.from(json['pendingChallenge'] as Map),
            );
      final restoredPhase = MatchPhase.values.byName(json['phase'] as String);

      scores
        ..clear()
        ..addAll(restoredScores);
      for (var index = 0; index < players.length; index++) {
        players[index].hand
          ..clear()
          ..addAll(restoredHands[index]);
        players[index].hiddenCards
          ..clear()
          ..addAll(
            restoredHiddenCards[index].where(restoredHands[index].contains),
          );
      }
      currentTrick
        ..clear()
        ..addAll(restoredCurrentTrick);
      playedCards
        ..clear()
        ..addAll(restoredPlayedCards);
      trickWinners
        ..clear()
        ..addAll(restoredTrickWinners);
      history
        ..clear()
        ..addAll(restoredHistory);
      _tenDecisionMade
        ..clear()
        ..addAll(restoredTenDecisionMade);
      _botChallengeConsideredThisTrick
        ..clear()
        ..addAll(restoredBotConsidered);
      _automaticTimeouts.setAll(0, restoredTimeouts);
      for (var index = 0; index < players.length; index++) {
        _playerSignalEmojis[index] = restoredSignals[index].emoji;
        _playerSignalExpiresAt[index] = restoredSignals[index].expiresAt;
      }

      dealerIndex = json['dealerIndex'] as int;
      trickLeaderIndex = json['trickLeaderIndex'] as int;
      currentPlayerIndex = json['currentPlayerIndex'] as int;
      handValue = json['handValue'] as int;
      nextTrickLeader = json['nextTrickLeader'] as int?;
      matchWinner = json['matchWinner'] as int?;
      lastChallengeTeam = json['lastChallengeTeam'] as int?;
      lastHandWinner = json['lastHandWinner'] as int?;
      lastHandPoints = json['lastHandPoints'] as int;
      lastCompletedHandNumber = json['lastCompletedHandNumber'] as int;
      lastCompletedHandWinnerTeam = json['lastCompletedHandWinnerTeam'] as int?;
      awaitingNextTrick = json['awaitingNextTrick'] as bool;
      challengeAttemptedThisTurn = json['challengeAttemptedThisTurn'] as bool;
      phase = restoredPhase;
      pendingChallenge = restoredPendingChallenge;
      challengeNotice = switch (json['challengeNotice']) {
        final String message => restoreMessage(message),
        _ => null,
      };
      challengeNoticeAccepted = json['challengeNoticeAccepted'] as bool;
      statusMessage = restoreMessage(json['statusMessage'] as String);
      notifyListeners();
      return true;
    } on Object {
      return false;
    }
  }

  static Map<String, Object> _playedCardToJson(PlayedCard play) => {
        'playerIndex': play.playerIndex,
        'card': play.card.code,
        if (play.hidden) 'hidden': true,
      };

  Map<String, Object>? _playerSignalToJson(int playerIndex, int now) {
    final emoji = _playerSignalEmojis[playerIndex];
    final remainingMs = _playerSignalExpiresAt[playerIndex] - now;
    if (emoji == null || remainingMs <= 0) return null;
    return {
      'emoji': emoji,
      'remainingMs': remainingMs,
    };
  }

  static List<PlayedCard> _playedCardList(Object? value) =>
      (value as List<Object?>).map((entry) {
        final map = Map<String, dynamic>.from(entry as Map);
        return PlayedCard(
          playerIndex: map['playerIndex'] as int,
          card: PlayingCard.fromCode(map['card'] as String),
          hidden: map['hidden'] as bool? ?? false,
        );
      }).toList();

  static List<int> _intList(Object? value, {required int length}) {
    final list = (value as List<Object?>).cast<int>();
    if (list.length != length) throw const FormatException('Lista inválida.');
    return list;
  }

  static List<({String? emoji, int expiresAt})> _playerSignalList(
    Object? value, {
    required int length,
  }) {
    final empty = List<({String? emoji, int expiresAt})>.generate(
      length,
      (_) => (emoji: null, expiresAt: 0),
    );
    if (value is! List || value.length != length) return empty;

    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final entry in value)
        if (entry is Map)
          switch (Map<String, dynamic>.from(entry)) {
            {
              'emoji': final String emoji,
              'remainingMs': final num remainingMs,
            }
                when emoji.isNotEmpty && remainingMs > 0 =>
              (emoji: emoji, expiresAt: now + remainingMs.toInt()),
            _ => (emoji: null, expiresAt: 0),
          }
        else
          (emoji: null, expiresAt: 0),
    ];
  }

  static String _swapTeamPerspective(String message) {
    var result = message;
    const pairs = <(String, String)>[
      ('Seu trio', 'O trio adversário'),
      ('seu trio', 'o trio adversário'),
      ('Nós', 'Eles'),
      ('nós', 'eles'),
    ];
    for (var index = 0; index < pairs.length; index++) {
      final (ours, theirs) = pairs[index];
      final marker = '\u0000team-perspective-$index\u0000';
      result = result
          .replaceAll(ours, marker)
          .replaceAll(theirs, ours)
          .replaceAll(marker, theirs);
    }
    const conjugations = <String, String>{
      'Nós venceram': 'Nós vencemos',
      'Eles vencemos': 'Eles venceram',
      'Nós ganharam': 'Nós ganhamos',
      'Eles ganhamos': 'Eles ganharam',
      'Nós marcaram': 'Nós marcamos',
      'Eles marcamos': 'Eles marcaram',
      'Nós decidiram': 'Nós decidimos',
      'Eles decidimos': 'Eles decidiram',
      'Nós aceitaram': 'Nós aceitamos',
      'Eles aceitamos': 'Eles aceitaram',
      'Nós correram': 'Nós corremos',
      'Eles corremos': 'Eles correram',
    };
    for (final entry in conjugations.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    const legacyConjugations = <String, String>{
      'Nós venceu': 'Nós vencemos',
      'Eles venceu': 'Eles venceram',
      'Nós ganhou': 'Nós ganhamos',
      'Eles ganhou': 'Eles ganharam',
      'Nós marcou': 'Nós marcamos',
      'Eles marcou': 'Eles marcaram',
    };
    for (final entry in legacyConjugations.entries) {
      result = result.replaceAll(RegExp('${entry.key}\\b'), entry.value);
    }
    return result;
  }

  static Challenge _challengeFromJson(Map<String, dynamic> json) => Challenge(
        challengerTeam: json['challengerTeam'] as int,
        challengerPlayer: json['challengerPlayer'] as int? ??
            ((json['responderPlayer'] as int) + 5) % 6,
        targetTeam: json['targetTeam'] as int,
        requestedValue: json['requestedValue'] as int,
        responderPlayer: json['responderPlayer'] as int,
      );

  void restart() {
    scores
      ..clear()
      ..addAll([0, 0]);
    history.clear();
    _automaticTimeouts.fillRange(0, _automaticTimeouts.length, 0);
    final firstPlayerIndex = _random.nextInt(players.length);
    dealerIndex = (firstPlayerIndex + players.length - 1) % players.length;
    matchWinner = null;
    _dealHand(rotateDealer: false);
  }

  void startNextHand() {
    if (phase != MatchPhase.handFinished) return;
    if (matchWinner != null) {
      phase = MatchPhase.gameOver;
      statusMessage = '${teamWon(matchWinner!, 'a partida')}!';
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
      player.hiddenCards.clear();
    }
    for (var round = 0; round < 3; round++) {
      for (var offset = 1; offset <= players.length; offset++) {
        final playerIndex = (dealerIndex + offset) % players.length;
        players[playerIndex].hand.add(deck.removeLast());
      }
    }

    trickLeaderIndex = (dealerIndex + 1) % players.length;
    currentPlayerIndex = trickLeaderIndex;
    handValue = isTenHand ? 2 : 1;
    _tenDecisionMade[0] = isTenToTen || scores[0] != 10;
    _tenDecisionMade[1] = isTenToTen || scores[1] != 10;
    statusMessage = isTenToTen
        ? 'Dez a dez: jogo obrigatório, cartas fechadas e valendo 4.'
        : isTenHand
            ? 'Mão de dez: sem desafios, valendo 4.'
            : 'Nova disputa: ${players[currentPlayerIndex].name} começa.';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void chooseToPlayTenHand() {
    if (!humanTenDecisionPending) return;
    _tenDecisionMade[humanTeam] = true;
    statusMessage = 'Seu trio decidiu jogar a mão de dez.';
    challengeNotice = statusMessage;
    challengeNoticeAccepted = true;
    _addHistory(statusMessage);
    notifyListeners();
  }

  void foldHumanTenHand() {
    if (!humanTenDecisionPending) return;
    _tenDecisionMade[humanTeam] = true;
    const message = 'Seu trio correu na mão de dez.';
    challengeNotice = message;
    challengeNoticeAccepted = false;
    _finishHand(
      1 - humanTeam,
      points: 1,
      reason: message,
    );
  }

  void resolveBotTenHand() {
    if (!botTenDecisionPending) return;
    final botTeam = 1 - humanTeam;
    _tenDecisionMade[botTeam] = true;
    final cards = players
        .where((player) => player.team == botTeam)
        .expand((player) => player.hand)
        .map((card) => card.strength)
        .toList();
    cards.sort();
    final confidence = cards.reversed.take(3).fold<int>(0, (a, b) => a + b);
    if (confidence < 19 && _random.nextDouble() < .65) {
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
  }

  void playHumanCard(PlayingCard card) {
    if (!isHumanTurn || !players[humanPlayerIndex].hand.contains(card)) return;
    _playCard(humanPlayerIndex, card);
  }

  bool isHumanCardHidden(PlayingCard card) =>
      players[humanPlayerIndex].hiddenCards.contains(card);

  int hiddenPlaysForTeam(int team) => currentTrick
      .where((play) => play.hidden && players[play.playerIndex].team == team)
      .length;

  bool canHumanHideCard(PlayingCard card) {
    if (isTenHand ||
        !isHumanTurn ||
        !players[humanPlayerIndex].hand.contains(card)) {
      return false;
    }
    return isHumanCardHidden(card) || hiddenPlaysForTeam(humanTeam) < 2;
  }

  void toggleHumanCardHidden(PlayingCard card) {
    if (!canHumanHideCard(card)) return;
    final hiddenCards = players[humanPlayerIndex].hiddenCards;
    if (!hiddenCards.remove(card)) {
      hiddenCards
        ..clear()
        ..add(card);
    }
    notifyListeners();
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
        currentPlayerIndex == humanPlayerIndex ||
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
    final visibleTrick = currentTrick.where((play) => !play.hidden).toList();
    if (visibleTrick.isEmpty) {
      if (trickWinners.isNotEmpty && trickWinners.first == player.team) {
        return cards.first;
      }
      if (cards.length >= 2 && _random.nextDouble() < .65) return cards[1];
      return cards.last;
    }

    final topStrength =
        visibleTrick.map((play) => play.card.strength).reduce(max);
    final topTeams = visibleTrick
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
      tableIsEmpty: currentTrick.every((play) => play.hidden),
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
      ...playedCards
          .where((play) => !play.hidden)
          .map((play) => play.card.code),
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

    final visibleTrick = currentTrick.where((play) => !play.hidden).toList();
    if (visibleTrick.isNotEmpty) {
      final topStrength =
          visibleTrick.map((play) => play.card.strength).reduce(max);
      final topTeams = visibleTrick
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
        visibleTrick.isNotEmpty &&
        !_teamCurrentlyLeadsTrick(player.team)) {
      confidence -= .10;
    }
    return confidence.clamp(0.0, 1.0);
  }

  bool _teamCurrentlyLeadsTrick(int team) {
    final visibleTrick = currentTrick.where((play) => !play.hidden).toList();
    if (visibleTrick.isEmpty) return false;
    final topStrength =
        visibleTrick.map((play) => play.card.strength).reduce(max);
    final topTeams = visibleTrick
        .where((play) => play.card.strength == topStrength)
        .map((play) => players[play.playerIndex].team)
        .toSet();
    return topTeams.length == 1 && topTeams.single == team;
  }

  bool _currentTrickIsLockedAgainst(int team) {
    final visibleTrick = currentTrick.where((play) => !play.hidden).toList();
    if (visibleTrick.isEmpty) return false;

    final playersWhoAlreadyPlayed =
        currentTrick.map((play) => play.playerIndex).toSet();
    final remainingTeamCards = <({int playerIndex, PlayingCard card})>[
      for (final player in players)
        if (player.team == team && !playersWhoAlreadyPlayed.contains(player.id))
          for (final card in player.hand) (playerIndex: player.id, card: card),
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
  }

  void requestHumanChallenge() {
    if (!canHumanChallenge) return;
    _requestChallenge(humanTeam, humanPlayerIndex);
  }

  void _requestChallenge(int team, int playerIndex) {
    final requested = nextChallengeValue;
    if (requested == null || !canTeamRequestChallenge(team)) return;
    challengeAttemptedThisTurn = true;
    lastChallengeTeam = team;
    pendingChallenge = Challenge(
      challengerTeam: team,
      challengerPlayer: playerIndex,
      targetTeam: 1 - team,
      requestedValue: requested,
      responderPlayer: _nextPlayerOnTeam(playerIndex, 1 - team),
    );
    final call = challengeLabelForPoints(requested);
    statusMessage = playerIndex == humanPlayerIndex
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
      showNotice: true,
    );
  }

  void foldHumanChallenge() {
    if (!humanMustAnswerChallenge) return;
    final challenge = pendingChallenge!;
    const message = 'Seu trio correu do desafio.';
    challengeNotice = message;
    challengeNoticeAccepted = false;
    _finishHand(
      challenge.challengerTeam,
      points: handValue,
      reason: message,
    );
  }

  void raiseHumanChallenge() {
    if (!humanMustAnswerChallenge || pendingChallenge!.requestedValue >= 6) {
      return;
    }
    _raiseChallenge(humanTeam, humanPlayerIndex);
  }

  void resolveBotChallenge() {
    final challenge = pendingChallenge;
    if (challenge == null || challenge.targetTeam == humanTeam) return;
    final botTeam = 1 - humanTeam;
    _botChallengeConsideredThisTrick[botTeam] = true;

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
    final foldingLosesMatch =
        scores[challenge.challengerTeam] + scorePointsForHandValue(handValue) >=
            12;
    final votes = _consultBotTeam(botTeam, challenge.requestedValue);
    final folds = votes.where((vote) => vote == ChallengeDecision.fold).length;
    final raises =
        votes.where((vote) => vote == ChallengeDecision.raise).length;
    final accepts =
        votes.where((vote) => vote == ChallengeDecision.accept).length;

    // O trio decide pelos sinais: um parceiro muito confiante evita uma fuga
    // precipitada, mas o aumento exige apoio de pelo menos dois robôs.
    if (!foldingLosesMatch && folds >= 2 && raises == 0) {
      challengeNotice = 'O trio adversário conversou e correu do desafio.';
      challengeNoticeAccepted = false;
      _finishHand(
        challenge.challengerTeam,
        points: handValue,
        reason: 'O trio adversário conversou e correu do desafio.',
      );
    } else if (_random.nextDouble() <
        botRaiseResponseProbability(
          raiseVotes: raises,
          acceptVotes: accepts,
          requestedValue: challenge.requestedValue,
        )) {
      _raiseChallenge(botTeam, challenge.responderPlayer);
    } else {
      _acceptChallenge(
        'O trio adversário conversou e aceitou: vale ${spokenValueForPoints(challenge.requestedValue)}.',
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
      challengerPlayer: playerIndex,
      targetTeam: 1 - raisingTeam,
      requestedValue: requested,
      responderPlayer: _nextPlayerOnTeam(playerIndex, 1 - raisingTeam),
    );
    statusMessage = playerIndex == humanPlayerIndex
        ? '${players[playerIndex].name} pediu ${challengeLabelForPoints(requested)}'
        : '${players[playerIndex].name} consultou os parceiros e pediu ${challengeLabelForPoints(requested)}';
    _addHistory(statusMessage);
    notifyListeners();
  }

  void _playCard(int playerIndex, PlayingCard card) {
    final player = players[playerIndex];
    player.hand.remove(card);
    final requestedHidden = player.hiddenCards.remove(card);
    final hidden =
        requestedHidden && !isTenHand && hiddenPlaysForTeam(player.team) < 2;
    final play = PlayedCard(
      playerIndex: playerIndex,
      card: card,
      hidden: hidden,
    );
    currentTrick.add(play);
    playedCards.add(play);
    statusMessage = hidden
        ? '${player.name} descartou uma carta fechada.'
        : '${player.name} jogou ${card.displayName}.';
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
          '${teamWon(winner.team, 'a ${trickWinners.length}ª mão')}.';
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
    final scorePoints = scorePointsForHandValue(points);
    scores[winningTeam] += scorePoints;
    lastHandWinner = winningTeam;
    lastHandPoints = scorePoints;
    statusMessage = '$reason ${teamScored(winningTeam, scorePoints)}';
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
    final visiblePlays = plays.where((play) => !play.hidden).toList();
    if (visiblePlays.isEmpty) return null;
    final maxStrength =
        visiblePlays.map((play) => play.card.strength).reduce(max);
    final strongest = visiblePlays
        .where((play) => play.card.strength == maxStrength)
        .toList();
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
