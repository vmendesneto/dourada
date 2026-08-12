import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/online/table_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const _savedGameKey = 'douradinha_partida_em_andamento_v1';

  late final DouradinhaGame game;
  late final TableSession tableSession;
  late final Future<SharedPreferences> _preferences;
  Future<void> _saveQueue = Future.value();
  Timer? _automationTimer;
  Timer? _turnTicker;
  Timer? _challengeNoticeTimer;
  bool _automationScheduled = false;
  String? _scheduledChallengeNotice;
  int? _clockPlayerIndex;
  DateTime? _turnDeadline;
  int _turnLimitSeconds = 15;
  int _turnSecondsLeft = 15;
  double _turnProgress = 1;
  bool _restoringGame = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    game = DouradinhaGame()..addListener(_onGameChanged);
    tableSession = TableSession()..addListener(_onTableSessionChanged);
    _preferences = SharedPreferences.getInstance();
    unawaited(_restoreSavedGame());
  }

  @override
  void dispose() {
    _automationTimer?.cancel();
    _turnTicker?.cancel();
    _challengeNoticeTimer?.cancel();
    tableSession
      ..removeListener(_onTableSessionChanged)
      ..dispose();
    game
      ..removeListener(_onGameChanged)
      ..dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (_restoringGame) {
      setState(() {});
      return;
    }
    _syncChallengeNotice();
    _syncTurnClock();
    setState(() {});
    _persistGame();
    tableSession.syncGame(game);
    _scheduleAutomation();
  }

  void _onTableSessionChanged() {
    if (!mounted) return;
    if (!tableSession.canPlayHere) {
      _automationTimer?.cancel();
      _automationScheduled = false;
      _stopTurnClock();
    } else if (!_restoringGame) {
      _syncTurnClock();
      _scheduleAutomation();
    }
    setState(() {});
  }

  Future<void> _restoreSavedGame() async {
    try {
      final preferences = await _preferences;
      final savedGame = preferences.getString(_savedGameKey);
      if (savedGame != null) {
        final decoded = jsonDecode(savedGame);
        if (decoded is Map) {
          game.restoreState(Map<String, dynamic>.from(decoded));
        }
      }
      await tableSession.initialize(game, preferences);
    } on Object {
      // Um salvamento antigo ou danificado não pode impedir o jogo de abrir.
    } finally {
      _restoringGame = false;
      if (mounted) {
        _syncChallengeNotice();
        _syncTurnClock();
        setState(() {});
        _persistGame();
        _scheduleAutomation();
      }
    }
  }

  void _persistGame() {
    final snapshot = jsonEncode(game.toJson());
    _saveQueue = _saveQueue.then((_) => _writeSavedGame(snapshot));
  }

  Future<void> _writeSavedGame(String snapshot) async {
    try {
      final preferences = await _preferences;
      await preferences.setString(_savedGameKey, snapshot);
    } on Object {
      // O jogo continua funcionando caso o navegador bloqueie o armazenamento.
    }
  }

  void _syncChallengeNotice() {
    final notice = game.challengeNotice;
    if (notice == null) {
      _challengeNoticeTimer?.cancel();
      _challengeNoticeTimer = null;
      _scheduledChallengeNotice = null;
      return;
    }
    if (_scheduledChallengeNotice == notice &&
        _challengeNoticeTimer?.isActive == true) {
      return;
    }
    _challengeNoticeTimer?.cancel();
    _scheduledChallengeNotice = notice;
    _challengeNoticeTimer = Timer(
      DouradinhaGame.challengeNoticeDuration,
      () {
        if (mounted) game.clearChallengeNotice();
      },
    );
  }

  void _syncTurnClock() {
    if (!mounted ||
        !tableSession.canPlayHere ||
        !game.canCurrentPlayerPlayCard) {
      _stopTurnClock();
      return;
    }

    final playerIndex = game.currentPlayerIndex;
    if (_clockPlayerIndex == playerIndex && _turnTicker?.isActive == true) {
      return;
    }

    _turnTicker?.cancel();
    _clockPlayerIndex = playerIndex;
    _turnLimitSeconds = game.timeLimitSecondsFor(playerIndex);
    _turnSecondsLeft = _turnLimitSeconds;
    _turnProgress = 1;
    _turnDeadline = DateTime.now().add(Duration(seconds: _turnLimitSeconds));
    _turnTicker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updateTurnClock(),
    );
  }

  void _stopTurnClock() {
    _turnTicker?.cancel();
    _turnTicker = null;
    _clockPlayerIndex = null;
    _turnDeadline = null;
    _turnProgress = 1;
  }

  void _updateTurnClock() {
    if (!mounted ||
        !game.canCurrentPlayerPlayCard ||
        game.currentPlayerIndex != _clockPlayerIndex) {
      _syncTurnClock();
      return;
    }

    final remaining = _turnDeadline!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _turnTicker?.cancel();
      _turnTicker = null;
      _turnProgress = 0;
      _turnSecondsLeft = 0;
      setState(() {});
      game.autoPlayCurrentPlayerOnTimeout();
      return;
    }

    _turnProgress = (remaining.inMilliseconds / (_turnLimitSeconds * 1000))
        .clamp(0.0, 1.0)
        .toDouble();
    _turnSecondsLeft = (remaining.inMilliseconds / 1000).ceil();
    setState(() {});
  }

  void _scheduleAutomation() {
    if (!mounted ||
        _restoringGame ||
        !tableSession.canPlayHere ||
        _automationScheduled) {
      return;
    }
    if (game.phase == MatchPhase.gameOver ||
        game.challengeNotice != null ||
        game.humanTenDecisionPending ||
        game.humanMustAnswerChallenge ||
        game.isHumanTurn) {
      return;
    }

    Duration delay;
    VoidCallback action;
    if (game.phase == MatchPhase.handFinished) {
      delay = DouradinhaGame.handResultDisplayDuration;
      action = game.startNextHand;
    } else if (game.awaitingNextTrick) {
      delay = DouradinhaGame.handResultDisplayDuration;
      action = game.beginNextTrick;
    } else if (game.botTenDecisionPending) {
      delay = const Duration(milliseconds: 900);
      action = game.resolveBotTenHand;
    } else if (game.pendingChallenge != null) {
      delay = const Duration(milliseconds: 900);
      action = game.resolveBotChallenge;
    } else if (game.currentPlayerIndex > 0) {
      delay = const Duration(milliseconds: 650);
      action = game.takeBotTurn;
    } else {
      return;
    }

    _automationScheduled = true;
    _automationTimer = Timer(delay, () {
      _automationScheduled = false;
      if (mounted) action();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF073B2A),
      body: SafeArea(
        child: Column(
          children: [
            _ScoreBoard(game: game, tableSession: tableSession),
            Expanded(child: _buildTable()),
            _HumanControls(
              game: game,
              clockActive: _clockPlayerIndex == 0,
              turnProgress: _turnProgress,
              secondsLeft: _turnSecondsLeft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 250;
        final tableSize = math.min(
          constraints.maxWidth * .88,
          constraints.maxHeight * .96,
        );

        Widget botSeat(int playerIndex, Alignment alignment) => Align(
              alignment: alignment,
              child: _BotSeat(
                game: game,
                playerIndex: playerIndex,
                compact: compact,
                clockActive: _clockPlayerIndex == playerIndex,
                turnProgress: _turnProgress,
                secondsLeft: _turnSecondsLeft,
              ),
            );

        Widget playedCard(int playerIndex, Alignment alignment) => Align(
              alignment: alignment,
              child: _PlayedCardAtSeat(
                game: game,
                playerIndex: playerIndex,
                compact: compact,
              ),
            );

        return Stack(
          children: [
            Center(
              child: SizedBox.square(
                dimension: tableSize,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF147A4E), Color(0xFF095037)],
                          ),
                          border: Border.all(
                            color: const Color(0xFFB8964B),
                            width: 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    botSeat(2, const Alignment(-.88, -.48)),
                    botSeat(3, const Alignment(0, -.88)),
                    botSeat(4, const Alignment(.88, -.48)),
                    botSeat(1, const Alignment(-.88, .48)),
                    botSeat(5, const Alignment(.88, .48)),
                    playedCard(2, const Alignment(-.48, -.26)),
                    playedCard(3, const Alignment(0, -.38)),
                    playedCard(4, const Alignment(.48, -.26)),
                    playedCard(1, const Alignment(-.48, .26)),
                    playedCard(5, const Alignment(.48, .26)),
                    playedCard(0, const Alignment(0, .58)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 8,
              child: _FootLegend(game: game),
            ),
            const Positioned(
              right: 18,
              bottom: 8,
              child: _ManilhasButton(),
            ),
            if (game.humanMustAnswerChallenge)
              Positioned.fill(child: _ChallengeOverlay(game: game)),
            if (game.humanTenDecisionPending)
              Positioned.fill(child: _TenHandOverlay(game: game)),
            if (game.awaitingNextTrick || game.phase == MatchPhase.handFinished)
              Positioned.fill(child: _HandResultOverlay(game: game)),
            if (game.challengeNotice != null)
              Positioned.fill(child: _ChallengeNoticeOverlay(game: game)),
            if (game.phase == MatchPhase.gameOver)
              Positioned.fill(
                child: _WinnerOverlay(
                  game: game,
                  onPlayAgain: () => unawaited(
                    tableSession.startNewMatch(game),
                  ),
                ),
              ),
            if (!tableSession.canPlayHere)
              Positioned.fill(
                child: _ReconnectingOverlay(tableSession: tableSession),
              ),
          ],
        );
      },
    );
  }
}

class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({required this.game, required this.tableSession});

  final DouradinhaGame game;
  final TableSession tableSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF052D22),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Row(
        children: [
          _TeamScore(
            label: game.teamOneLabel,
            score: game.scores[0],
            color: const Color(0xFF5CB6FF),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('×',
                style: TextStyle(fontSize: 24, color: Colors.white54)),
          ),
          _TeamScore(
            label: game.teamTwoLabel,
            score: game.scores[1],
            color: const Color(0xFFFFC857),
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 38, color: Colors.white24),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HandWinnerDots(results: game.trickWinners),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        '${game.displayedHandNumber}ª Mão • Vale ${DouradinhaGame.spokenValueForPoints(game.handValue)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  game.statusMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: tableSession.errorMessage ?? tableSession.connectionLabel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tableSession.connected ? Icons.cloud_done : Icons.cloud_off,
                  size: 16,
                  color: tableSession.connected
                      ? const Color(0xFF7CE0A3)
                      : Colors.white54,
                ),
                const SizedBox(width: 5),
                Text(
                  tableSession.connectionLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandWinnerDots extends StatelessWidget {
  const _HandWinnerDots({required this.results});

  final List<int?> results;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final wasPlayed = index < results.length;
        final winner = wasPlayed ? results[index] : null;
        final label = !wasPlayed
            ? '${index + 1}ª mão: ainda não jogada'
            : winner == null
                ? '${index + 1}ª mão: empate'
                : '${index + 1}ª mão: ${winner == 0 ? 'Trio Azul' : 'Trio Dourado'}';
        final color = !wasPlayed
            ? Colors.transparent
            : winner == null
                ? Colors.white38
                : winner == 0
                    ? const Color(0xFF5CB6FF)
                    : const Color(0xFFFFC857);
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: label,
            child: Semantics(
              label: label,
              child: Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: wasPlayed ? Colors.white54 : Colors.white24,
                  ),
                ),
                child: wasPlayed && winner == null
                    ? const Text(
                        '=',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: .9,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore(
      {required this.label, required this.score, required this.color});

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 38,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12)),
            Text('$score',
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, height: 1)),
          ],
        ),
      ],
    );
  }
}

class _BotSeat extends StatelessWidget {
  const _BotSeat({
    required this.game,
    required this.playerIndex,
    required this.compact,
    required this.clockActive,
    required this.turnProgress,
    required this.secondsLeft,
  });

  final DouradinhaGame game;
  final int playerIndex;
  final bool compact;
  final bool clockActive;
  final double turnProgress;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final player = game.players[playerIndex];
    final active = game.currentPlayerIndex == playerIndex &&
        game.phase == MatchPhase.playing &&
        !game.awaitingNextTrick;
    final teamColor =
        player.team == 0 ? const Color(0xFF5CB6FF) : const Color(0xFFFFC857);
    final reveal = game.canHumanSeePartnerCardsInTenHand && player.team == 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 3 : 6),
      decoration: BoxDecoration(
        color:
            active ? teamColor.withValues(alpha: .22) : const Color(0xB8052D22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? teamColor : Colors.white12, width: active ? 2 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: compact ? 10 : 13,
                backgroundColor: teamColor,
                child: const Icon(Icons.smart_toy_outlined,
                    color: Color(0xFF052D22), size: 16),
              ),
              const SizedBox(width: 6),
              Text(
                player.name,
                style: TextStyle(
                    color: teamColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              if (game.footIndex == playerIndex)
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: Text('PÉ',
                      style: TextStyle(color: Colors.white60, fontSize: 9)),
                ),
            ],
          ),
          if (clockActive) ...[
            const SizedBox(height: 4),
            _TurnProgress(
              progress: turnProgress,
              secondsLeft: secondsLeft,
              width: 94,
            ),
          ],
          if (!compact || reveal) ...[
            const SizedBox(height: 4),
            Row(
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
        ],
      ),
    );
  }
}

class _PlayedCardAtSeat extends StatelessWidget {
  const _PlayedCardAtSeat({
    required this.game,
    required this.playerIndex,
    required this.compact,
  });

  final DouradinhaGame game;
  final int playerIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    PlayedCard? playedCard;
    for (final play in game.currentTrick) {
      if (play.playerIndex == playerIndex) {
        playedCard = play;
        break;
      }
    }
    if (playedCard == null) return const SizedBox.shrink();

    final teamColor = game.players[playerIndex].team == 0
        ? const Color(0xFF5CB6FF)
        : const Color(0xFFFFC857);
    final width = compact ? 50.0 : 60.0;
    final height = compact ? 74.0 : 88.0;
    final resultIsVisible =
        game.awaitingNextTrick || game.phase == MatchPhase.handFinished;
    final greatestStrength = game.currentTrick.fold<int>(
      0,
      (greatest, play) =>
          play.card.strength > greatest ? play.card.strength : greatest,
    );
    final isGreatestCard =
        resultIsVisible && playedCard.card.strength == greatestStrength;

    return _WinningCardPulse(
      key: ValueKey('${playedCard.card.code}-$playerIndex'),
      active: isGreatestCard,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: teamColor,
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: teamColor.withValues(alpha: .42),
              blurRadius: 10,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Colors.black45,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: _CardFace(card: playedCard.card, width: width, height: height),
      ),
    );
  }
}

class _WinningCardPulse extends StatefulWidget {
  const _WinningCardPulse({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_WinningCardPulse> createState() => _WinningCardPulseState();
}

class _WinningCardPulseState extends State<_WinningCardPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _WinningCardPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        if (!widget.active) return child!;
        final progress = _pulse.value;
        return Transform.scale(
          scale: 1 + (.13 * progress),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFE66D)
                      .withValues(alpha: .45 + (.4 * progress)),
                  blurRadius: 12 + (14 * progress),
                  spreadRadius: 2 + (4 * progress),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _HumanControls extends StatelessWidget {
  const _HumanControls({
    required this.game,
    required this.clockActive,
    required this.turnProgress,
    required this.secondsLeft,
  });

  final DouradinhaGame game;
  final bool clockActive;
  final double turnProgress;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final human = game.players[0];
    final active = game.isHumanTurn;
    return Container(
      height: 126,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFF052D22),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 70,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF5CB6FF) : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('VOCÊ',
                  style: TextStyle(
                      color: Color(0xFF5CB6FF), fontWeight: FontWeight.bold)),
              Text(
                active ? 'Sua vez' : 'Aguarde',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              if (clockActive) ...[
                const SizedBox(height: 6),
                _TurnProgress(
                  progress: turnProgress,
                  secondsLeft: secondsLeft,
                  width: 105,
                ),
              ],
              if (game.footIndex == 0)
                const Text('PÉ',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final card in human.hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _PlayableCard(
                      card: card,
                      enabled: active,
                      onTap: () => game.playHumanCard(card),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: FilledButton.icon(
              onPressed:
                  game.canHumanChallenge ? game.requestHumanChallenge : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE9A23B),
                foregroundColor: const Color(0xFF271500),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.campaign),
              label: Text(
                game.challengeButtonLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnProgress extends StatelessWidget {
  const _TurnProgress({
    required this.progress,
    required this.secondsLeft,
    required this.width,
  });

  final double progress;
  final int secondsLeft;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = progress > .5
        ? const Color(0xFF63E6A5)
        : progress > .25
            ? const Color(0xFFFFC857)
            : const Color(0xFFFF6B6B);
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: color,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${secondsLeft}s',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayableCard extends StatefulWidget {
  const _PlayableCard(
      {required this.card, required this.enabled, required this.onTap});

  final PlayingCard card;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PlayableCard> createState() => _PlayableCardState();
}

class _PlayableCardState extends State<_PlayableCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: hovered && widget.enabled ? 1.08 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : .68,
          duration: const Duration(milliseconds: 180),
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(7),
            child: _CardFace(card: widget.card, width: 67, height: 98),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace(
      {required this.card, required this.width, required this.height});

  final PlayingCard card;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFDDDDDD)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/cartas/${card.code}.png',
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) => Center(
          child: Text(card.code,
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF8E2333),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF2D6A2), width: 1.5),
      ),
      child: const Icon(Icons.auto_awesome, color: Color(0xFFF2D6A2), size: 12),
    );
  }
}

class _ChallengeOverlay extends StatelessWidget {
  const _ChallengeOverlay({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    final challenge = game.pendingChallenge!;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          color: const Color(0xFF123C30),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign, color: Color(0xFFFFC857), size: 36),
                Text(
                  DouradinhaGame.challengeLabelForPoints(
                    challenge.requestedValue,
                  ),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text('O Trio Dourado desafiou o seu trio.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                        onPressed: game.foldHumanChallenge,
                        child: const Text('CORRER')),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: game.acceptHumanChallenge,
                        child: const Text('ACEITAR')),
                    if (challenge.requestedValue < 6) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: game.raiseHumanChallenge,
                        child: Text(DouradinhaGame.challengeLabelForPoints(
                          DouradinhaGame.nextChallengeAfter(
                            challenge.requestedValue,
                          )!,
                        )),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeNoticeOverlay extends StatelessWidget {
  const _ChallengeNoticeOverlay({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    final accepted = game.challengeNoticeAccepted;
    final color = accepted ? const Color(0xFF63E6A5) : const Color(0xFFFFC857);
    return ColoredBox(
      color: Colors.black.withValues(alpha: .45),
      child: Center(
        child: Card(
          color: const Color(0xFF123C30),
          child: SizedBox(
            width: 370,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    accepted ? Icons.check_circle : Icons.directions_run,
                    color: color,
                    size: 42,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    accepted ? 'DESAFIO ACEITO' : 'O TRIO DOURADO CORREU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    game.challengeNotice!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (!accepted) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'O Trio Azul venceu a disputa.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1, end: 0),
                    duration: DouradinhaGame.challengeNoticeDuration,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      color: color,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TenHandOverlay extends StatelessWidget {
  const _TenHandOverlay({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          color: const Color(0xFF123C30),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('MÃO DE DEZ',
                    style: TextStyle(
                        color: Color(0xFFFFC857),
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text(
                  'As cartas dos parceiros estão abertas para consulta.\nSem Truco ou aumentos; jogando, a mão vale 4.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: game.foldHumanTenHand,
                      child: const Text('CORRER (CEDE 2)'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: game.chooseToPlayTenHand,
                      child: const Text('JOGAR A MÃO'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HandResultOverlay extends StatelessWidget {
  const _HandResultOverlay({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    final completedHand = game.lastCompletedHandNumber;
    final winnerTeam = game.lastCompletedHandWinnerTeam;
    final contestEnded = game.phase == MatchPhase.handFinished;
    final resultTeam = winnerTeam ?? game.lastHandWinner;
    final teamColor = resultTeam == null
        ? Colors.white70
        : resultTeam == 0
            ? const Color(0xFF5CB6FF)
            : const Color(0xFFFFC857);
    final teamName = resultTeam == null
        ? 'Empate'
        : resultTeam == 0
            ? game.teamOneLabel
            : game.teamTwoLabel;

    final nextMessage = game.matchWinner != null
        ? 'Resultado em 5 segundos…'
        : contestEnded
            ? 'Nova disputa em 5 segundos…'
            : 'Próxima mão em 5 segundos…';
    final disputeSummary = game.lastHandWinner == null
        ? 'Três mãos empatadas: nenhum tento.'
        : '${game.lastHandWinner == 0 ? game.teamOneLabel : game.teamTwoLabel} marcou ${game.lastHandPoints}.';
    final strongestPlays = <PlayedCard>[];
    if (game.currentTrick.isNotEmpty) {
      final greatestStrength = game.currentTrick.fold<int>(
        0,
        (greatest, play) =>
            play.card.strength > greatest ? play.card.strength : greatest,
      );
      strongestPlays.addAll(
        game.currentTrick.where(
          (play) => play.card.strength == greatestStrength,
        ),
      );
    }

    final featuredCards = <PlayingCard>[];
    if (winnerTeam != null && strongestPlays.isNotEmpty) {
      featuredCards.add(
        strongestPlays
            .firstWhere(
              (play) => game.players[play.playerIndex].team == winnerTeam,
            )
            .card,
      );
    } else {
      final representedTeams = <int>{};
      for (final play in strongestPlays) {
        final team = game.players[play.playerIndex].team;
        if (representedTeams.add(team)) featuredCards.add(play.card);
      }
    }

    final resultMessage = completedHand == 0
        ? '$teamName venceu a disputa!'
        : winnerTeam == null
            ? 'A mão empatou com cartas de mesma força'
            : '$teamName venceu a mão com '
                '${featuredCards.first.isManilha ? featuredCards.first.displayName : featuredCards.first.rankName}';

    return Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        widthFactor: .72,
        child: Card(
          margin: const EdgeInsets.only(top: 8),
          color: const Color(0xF5123C30),
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (featuredCards.isEmpty)
                  Icon(Icons.emoji_events, color: teamColor, size: 34)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final card in featuredCards)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: teamColor,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: _CardFace(
                              card: card,
                              width: 38,
                              height: 56,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        completedHand > 0
                            ? '$completedHandª MÃO'
                            : 'FIM DA DISPUTA',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        resultMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: teamColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (contestEnded && completedHand > 0)
                        Text(
                          disputeSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Vale ${DouradinhaGame.spokenValueForPoints(game.handValue)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      HandResultProgress(
                        key: ValueKey(
                          'resultado-${game.playedCards.length}-$completedHand-${game.phase.name}',
                        ),
                        color: teamColor,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nextMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HandResultProgress extends StatefulWidget {
  const HandResultProgress({
    super.key,
    required this.color,
    this.duration = DouradinhaGame.handResultDisplayDuration,
  });

  final Color color;
  final Duration duration;

  @override
  State<HandResultProgress> createState() => _HandResultProgressState();
}

class _HandResultProgressState extends State<HandResultProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      // Esta barra é um relógio, não um efeito decorativo. Ela precisa
      // durar cinco segundos mesmo quando o navegador reduz animações.
      animationBehavior: AnimationBehavior.preserve,
    )..forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant HandResultProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LinearProgressIndicator(
        key: const ValueKey('barra-resultado-mao'),
        value: 1 - _controller.value,
        minHeight: 7,
        borderRadius: BorderRadius.circular(4),
        color: widget.color,
        backgroundColor: Colors.white12,
      ),
    );
  }
}

class _WinnerOverlay extends StatelessWidget {
  const _WinnerOverlay({required this.game, required this.onPlayAgain});

  final DouradinhaGame game;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final humanWon = game.matchWinner == 0;
    return ColoredBox(
      color: Colors.black.withValues(alpha: .72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(humanWon ? Icons.emoji_events : Icons.sports_esports,
                color: const Color(0xFFFFC857), size: 62),
            const SizedBox(height: 8),
            Text(
              humanWon ? 'SEU TRIO VENCEU!' : 'O TRIO DOURADO VENCEU',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900),
            ),
            Text(
              '${game.scores[0]} × ${game.scores[1]}',
              style: const TextStyle(color: Colors.white70, fontSize: 22),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPlayAgain,
              icon: const Icon(Icons.replay),
              label: const Text('JOGAR NOVAMENTE'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReconnectingOverlay extends StatelessWidget {
  const _ReconnectingOverlay({required this.tableSession});

  final TableSession tableSession;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: .72),
      child: Center(
        child: Card(
          color: const Color(0xFF123C30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  'RECONECTANDO À MESA ${tableSession.tableNumber ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Um robô está jogando no seu lugar.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FootLegend extends StatelessWidget {
  const _FootLegend({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Pé da mão: ${game.players[game.footIndex].name}',
      style: const TextStyle(color: Colors.white54, fontSize: 10),
    );
  }
}

class _ManilhasButton extends StatelessWidget {
  const _ManilhasButton();

  static const cardsFromWeakestToStrongest = [
    PlayingCard('7', 'o'),
    PlayingCard('A', 'e'),
    PlayingCard('7', 'c'),
    PlayingCard('4', 'p'),
    PlayingCard('5', 'p'),
    PlayingCard('A', 'p'),
    PlayingCard('2', 'p'),
    PlayingCard('J', 'p'),
    PlayingCard('Q', 'o'),
  ];

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Consultar manilhas',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF123C30),
        builder: (context) => FractionallySizedBox(
          heightFactor: .9,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFFFC857)),
                      SizedBox(width: 9),
                      Text(
                        'MANILHAS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Spacer(),
                      Text(
                        'MAIOR ↑',
                        style: TextStyle(
                          color: Color(0xFFFFC857),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 3, bottom: 10),
                    child: Text(
                      'Da menor, embaixo, para a maior carta do jogo, no topo.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      reverse: true,
                      itemCount: cardsFromWeakestToStrongest.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final card = cardsFromWeakestToStrongest[index];
                        final isStrongest =
                            index == cardsFromWeakestToStrongest.length - 1;
                        return Container(
                          height: 58,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isStrongest
                                ? const Color(0x33FFC857)
                                : Colors.white.withValues(alpha: .055),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: isStrongest
                                  ? const Color(0x88FFC857)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${index + 1}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isStrongest
                                        ? const Color(0xFFFFC857)
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _CardFace(card: card, width: 34, height: 50),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  card.displayName,
                                  style: TextStyle(
                                    color: isStrongest
                                        ? const Color(0xFFFFD77E)
                                        : Colors.white,
                                    fontSize: 15,
                                    fontWeight: isStrongest
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isStrongest)
                                const Text(
                                  'MAIOR',
                                  style: TextStyle(
                                    color: Color(0xFFFFC857),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'MENOR • 7 de Ouros',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.auto_awesome, size: 18),
    );
  }
}
