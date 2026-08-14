import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dourada/auth/auth_service.dart';
import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/online/table_session.dart';
import 'package:dourada/platform/fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.entry});

  final TableEntry entry;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  static const _savedGameKey = 'douradinha_partida_em_andamento_v1';

  late final DouradinhaGame game;
  late final TableSession tableSession;
  late final Future<SharedPreferences> _preferences;
  Future<void> _saveQueue = Future.value();
  Timer? _automationTimer;
  Timer? _turnTicker;
  Timer? _challengeNoticeTimer;
  Timer? _challengeAnimationTimer;
  bool _automationScheduled = false;
  bool _challengeNoticeVisible = false;
  bool _challengeNoticeStarted = false;
  String? _scheduledChallengeNotice;
  final List<({String id, int playerIndex, int requestedValue})>
      _challengeAnimationQueue = [];
  final Set<String> _shownChallengeAnimations = {};
  ({String id, int playerIndex, int requestedValue})? _activeChallengeAnimation;
  int _lastObservedHistoryLength = 0;
  int? _clockPlayerIndex;
  DateTime? _turnDeadline;
  int _turnLimitSeconds = 15;
  int _turnSecondsLeft = 15;
  double _turnProgress = 1;
  bool _restoringGame = true;
  bool _leavingTable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    game = DouradinhaGame(humanPlayerIndex: widget.entry.seatIndex)
      ..configureSeats([
        for (final seat in widget.entry.seats)
          seat == null
              ? null
              : (
                  name: seat.name,
                  isHuman: !seat.isBot,
                  photoUrl: seat.photoUrl,
                ),
      ])
      ..addListener(_onGameChanged);
    tableSession = TableSession(entry: widget.entry)
      ..addListener(_onTableSessionChanged);
    _preferences = SharedPreferences.getInstance();
    unawaited(_restoreSavedGame());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _automationTimer?.cancel();
    _turnTicker?.cancel();
    _challengeNoticeTimer?.cancel();
    _challengeAnimationTimer?.cancel();
    tableSession
      ..removeListener(_onTableSessionChanged)
      ..dispose();
    game
      ..removeListener(_onGameChanged)
      ..dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(tableSession.resumePresence());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(tableSession.pausePresence());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (_restoringGame) {
      _syncChallengeAnimation();
      _syncChallengeNotice();
      setState(() {});
      return;
    }
    _syncChallengeAnimation();
    _syncChallengeNotice();
    _syncTurnClock();
    setState(() {});
    _persistGame();
    tableSession.syncGame(game);
    _scheduleAutomation();
  }

  Future<void> _confirmLeaveTable() async {
    if (_leavingTable) return;
    final waiting = tableSession.waiting;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF123C30),
            icon: const Icon(
              Icons.logout_rounded,
              color: Color(0xFFFFC857),
              size: 42,
            ),
            title: const Text(
              'SAIR DA MESA?',
              textAlign: TextAlign.center,
            ),
            content: Text(
              waiting
                  ? 'Sua cadeira será liberada e você voltará ao lobby. Não será possível retornar por esta sessão.'
                  : 'Um robô assumirá sua cadeira e você voltará ao lobby. Não será possível retornar para esta partida.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('CONTINUAR NA MESA'),
              ),
              FilledButton.icon(
                key: const ValueKey('confirmar-saida-mesa'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('SAIR'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _leavingTable = true);
    try {
      await tableSession.leaveTable();
      await exitGameFullscreen();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      setState(() => _leavingTable = false);
    }
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
      try {
        final savedGame = preferences.getString(_savedGameKey);
        if (!widget.entry.online && savedGame != null) {
          final decoded = jsonDecode(savedGame);
          if (decoded is Map) {
            game.restoreState(Map<String, dynamic>.from(decoded));
          }
        }
      } on Object {
        // Um salvamento antigo ou danificado não pode impedir o jogo de abrir.
      }
      await tableSession.initialize(game, preferences);
    } on Object {
      // A tela permanece disponível mesmo se o armazenamento falhar.
    } finally {
      _restoringGame = false;
      if (mounted) {
        _syncChallengeAnimation();
        _syncChallengeNotice();
        _syncTurnClock();
        setState(() {});
        _persistGame();
        _scheduleAutomation();
      }
    }
  }

  void _persistGame() {
    if (widget.entry.online) return;
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
      _challengeNoticeVisible = false;
      _challengeNoticeStarted = false;
      return;
    }
    if (_scheduledChallengeNotice == notice) return;
    _challengeNoticeTimer?.cancel();
    _scheduledChallengeNotice = notice;
    _challengeNoticeVisible = false;
    _challengeNoticeStarted = false;
    _startChallengeNoticeIfReady();
  }

  void _startChallengeNoticeIfReady() {
    if (_challengeNoticeStarted ||
        _scheduledChallengeNotice == null ||
        game.challengeNotice != _scheduledChallengeNotice ||
        _activeChallengeAnimation != null ||
        _challengeAnimationQueue.isNotEmpty) {
      return;
    }
    _challengeNoticeStarted = true;
    _challengeNoticeVisible = true;
    _challengeNoticeTimer = Timer(
      DouradinhaGame.challengeNoticeDuration,
      () {
        if (!mounted) return;
        if (tableSession.enabled) {
          setState(() => _challengeNoticeVisible = false);
        } else {
          game.clearChallengeNotice();
        }
      },
    );
  }

  void _syncChallengeAnimation() {
    final historyLength = game.history.length;
    if (historyLength < _lastObservedHistoryLength) {
      _challengeAnimationTimer?.cancel();
      _challengeAnimationTimer = null;
      _challengeAnimationQueue.clear();
      _shownChallengeAnimations.clear();
      _activeChallengeAnimation = null;
    }
    _lastObservedHistoryLength = historyLength;

    final challenge = game.pendingChallenge;
    if (challenge == null ||
        DouradinhaGame.challengeGifAssetForPoints(
              challenge.requestedValue,
            ) ==
            null) {
      return;
    }
    final animationId = [
      historyLength,
      challenge.challengerPlayer,
      challenge.requestedValue,
    ].join('-');
    if (!_shownChallengeAnimations.add(animationId)) return;
    _challengeAnimationQueue.add((
      id: animationId,
      playerIndex: challenge.challengerPlayer,
      requestedValue: challenge.requestedValue,
    ));
    _startNextChallengeAnimation();
  }

  void _startNextChallengeAnimation() {
    if (_activeChallengeAnimation != null || _challengeAnimationQueue.isEmpty) {
      return;
    }
    _activeChallengeAnimation = _challengeAnimationQueue.removeAt(0);
    _challengeAnimationTimer = Timer(
      DouradinhaGame.challengeAnimationDuration,
      () {
        if (!mounted) return;
        setState(() {
          _activeChallengeAnimation = null;
          _startNextChallengeAnimation();
          _startChallengeNoticeIfReady();
        });
      },
    );
  }

  void _syncTurnClock() {
    if (!mounted ||
        !tableSession.canPlayHere ||
        !game.canCurrentPlayerPlayCard ||
        (tableSession.serverControlsAutomation &&
            game.currentPlayerIndex != game.humanPlayerIndex)) {
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
        tableSession.serverControlsAutomation ||
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
      delay = game.matchWinner == null
          ? DouradinhaGame.betweenPartidasTransitionDuration
          : DouradinhaGame.handTransitionDuration;
      action = game.startNextHand;
    } else if (game.awaitingNextTrick) {
      delay = DouradinhaGame.handTransitionDuration;
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
    if (tableSession.waiting ||
        (tableSession.enabled && tableSession.phase == LobbyTablePhase.empty)) {
      return _WaitingRoom(
        session: tableSession,
        leaving: _leavingTable,
        onLeave: () => unawaited(_confirmLeaveTable()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF073B2A),
      body: SafeArea(
        child: Column(
          children: [
            _ScoreBoard(
              game: game,
              tableSession: tableSession,
              leaving: _leavingTable,
              onLeave: () => unawaited(_confirmLeaveTable()),
            ),
            Expanded(child: _buildTable()),
            _HumanControls(
              game: game,
              clockActive: _clockPlayerIndex == game.humanPlayerIndex,
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
        final phone = MediaQuery.sizeOf(context).width < 600;
        final compact = phone || constraints.maxHeight < 250;
        final tableSize = math.min(
          constraints.maxWidth * (phone ? .88 : .68),
          constraints.maxHeight *
              (phone
                  ? .78
                  : compact
                      ? .82
                      : .69),
        );
        final seatOutset = phone
            ? 10.0
            : compact
                ? 62.0
                : 102.0;
        final sideSeatX = phone ? .84 : .92;

        Widget botSeat(int playerIndex, Alignment alignment) => Align(
              alignment: alignment,
              child: Transform.translate(
                offset: Offset(
                  alignment.x * seatOutset,
                  alignment.y * seatOutset,
                ),
                child: _BotSeat(
                  game: game,
                  playerIndex: playerIndex,
                  compact: compact,
                  clockActive: _clockPlayerIndex == playerIndex,
                  turnProgress: _turnProgress,
                  secondsLeft: _turnSecondsLeft,
                ),
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

        final playedCardAlignments = <int, Alignment>{
          (game.humanPlayerIndex + 2) % 6: const Alignment(-.58, -.46),
          (game.humanPlayerIndex + 3) % 6: const Alignment(0, -.62),
          (game.humanPlayerIndex + 4) % 6: const Alignment(.58, -.46),
          (game.humanPlayerIndex + 1) % 6: const Alignment(-.58, .46),
          (game.humanPlayerIndex + 5) % 6: const Alignment(.58, .46),
          game.humanPlayerIndex: const Alignment(0, .62),
        };
        final challengeAnimation = _activeChallengeAnimation;

        return Stack(
          children: [
            Center(
              child: SizedBox.square(
                dimension: tableSize,
                child: Stack(
                  clipBehavior: Clip.none,
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
                    botSeat((game.humanPlayerIndex + 2) % 6,
                        Alignment(-sideSeatX, -.52)),
                    botSeat((game.humanPlayerIndex + 3) % 6,
                        const Alignment(0, -1)),
                    botSeat((game.humanPlayerIndex + 4) % 6,
                        Alignment(sideSeatX, -.52)),
                    botSeat((game.humanPlayerIndex + 1) % 6,
                        Alignment(-sideSeatX, .52)),
                    botSeat((game.humanPlayerIndex + 5) % 6,
                        Alignment(sideSeatX, .52)),
                    for (final entry in playedCardAlignments.entries)
                      playedCard(entry.key, entry.value),
                  ],
                ),
              ),
            ),
            Positioned(
              left: phone ? 6 : 18,
              bottom: phone ? 2 : 8,
              child: _FootLegend(game: game),
            ),
            Positioned(
              right: phone ? 6 : 18,
              bottom: phone ? 2 : 8,
              child: const _ManilhasButton(),
            ),
            if (game.humanMustAnswerChallenge)
              Positioned.fill(
                child: _ChallengeOverlay(
                  game: game,
                  tableSession: tableSession,
                ),
              ),
            if (game.humanTenDecisionPending)
              Positioned.fill(child: _TenHandOverlay(game: game)),
            if (game.challengeNotice != null && _challengeNoticeVisible)
              Positioned.fill(child: _ChallengeNoticeOverlay(game: game)),
            if (challengeAnimation != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: SizedBox.square(
                      dimension: tableSize,
                      child: Align(
                        alignment: playedCardAlignments[
                                challengeAnimation.playerIndex] ??
                            Alignment.center,
                        child: _ChallengeCallGif(
                          key: ValueKey('gif-desafio-${challengeAnimation.id}'),
                          requestedValue: challengeAnimation.requestedValue,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (game.phase == MatchPhase.gameOver)
              Positioned.fill(
                child: _WinnerOverlay(
                  game: game,
                  automaticReturn: tableSession.enabled,
                  onPlayAgain: tableSession.enabled
                      ? null
                      : () => unawaited(tableSession.startNewMatch(game)),
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

class _WaitingRoom extends StatefulWidget {
  const _WaitingRoom({
    required this.session,
    required this.leaving,
    required this.onLeave,
  });

  final TableSession session;
  final bool leaving;
  final VoidCallback onLeave;

  @override
  State<_WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<_WaitingRoom> {
  Timer? _countdownTicker;

  TableSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _countdownTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted &&
          (session.waitingStartAt != null || session.fillBotsVote != null)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countdownEnd = session.waitingStartAt;
    final remainingMilliseconds = countdownEnd == null
        ? 0
        : countdownEnd.difference(DateTime.now()).inMilliseconds.clamp(0, 5000);
    final countdownSeconds = (remainingMilliseconds / 1000).ceil();
    final countdownProgress = remainingMilliseconds / 5000;
    return Scaffold(
      backgroundColor: const Color(0xFF032C21),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF074333),
                      borderRadius: BorderRadius.circular(26),
                      border:
                          Border.all(color: const Color(0xFFD7A84C), width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('sair-mesa-espera'),
                              tooltip: 'Sair da mesa',
                              onPressed: widget.leaving ? null : widget.onLeave,
                              color: Colors.white,
                              icon: widget.leaving
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.logout_rounded),
                            ),
                            Expanded(
                              child: Text(
                                'MESA ${session.tableNumber}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFD46B),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'AGUARDANDO JOGADORES • ${session.playerCount}/6',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 18,
                          children: List.generate(6, (index) {
                            final seat = session.seats[index];
                            final color = index.isEven
                                ? const Color(0xFF5CB6FF)
                                : const Color(0xFFFFC857);
                            return SizedBox(
                              width: 78,
                              child: Column(
                                children: [
                                  if (seat == null)
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Colors.white.withValues(alpha: .05),
                                        border:
                                            Border.all(color: Colors.white24),
                                      ),
                                      child: const Icon(
                                        Icons.chair_outlined,
                                        color: Colors.white38,
                                        size: 29,
                                      ),
                                    )
                                  else
                                    _TablePlayerAvatar(
                                      key: ValueKey('avatar-jogador-$index'),
                                      isBot: seat.isBot,
                                      photoUrl: seat.photoUrl,
                                      color: color,
                                      radius: 27,
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    seat == null ? 'Vazia' : seat.name,
                                    key: index == session.seatIndex
                                        ? const ValueKey('nome-jogador-local')
                                        : null,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(color: color, fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),
                        if (countdownEnd != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC857)
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFFFC857)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '6 HUMANOS CONECTADOS',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: const Color(0xFFFFC857),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'A partida começa em $countdownSeconds ${countdownSeconds == 1 ? 'segundo' : 'segundos'}.',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  key: const ValueKey('contagem-seis-humanos'),
                                  value: countdownProgress,
                                  minHeight: 7,
                                  borderRadius: BorderRadius.circular(4),
                                  color: const Color(0xFFFFC857),
                                  backgroundColor: Colors.white12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ] else if (session.missingPlayers == 0) ...[
                          const Text(
                            'Aguardando os 6 jogadores estarem conectados para iniciar a contagem.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFFFFC857)),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            key: const ValueKey('colocar-robos'),
                            onPressed: session.connecting ||
                                    session.fillBotsVote != null ||
                                    session.missingPlayers == 0
                                ? null
                                : session.fillRemainingWithBots,
                            icon: const Icon(Icons.smart_toy_rounded),
                            label: Text(
                              session.missingPlayers == 0
                                  ? countdownEnd == null
                                      ? 'AGUARDANDO CONEXÃO DOS JOGADORES'
                                      : 'INÍCIO AUTOMÁTICO EM $countdownSeconds'
                                  : session.missingPlayers == 1
                                      ? 'COLOCAR 1 ROBÔ E INICIAR'
                                      : 'COLOCAR ${session.missingPlayers} ROBÔS E INICIAR',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE7A93E),
                              foregroundColor: const Color(0xFF173326),
                              textStyle:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        if (session.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(session.errorMessage!,
                              style: const TextStyle(color: Color(0xFFFF9E80))),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Seis humanos iniciam automaticamente. Você também pode preencher todas as cadeiras vazias com robôs.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .55)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (session.fillBotsVote != null || session.requestingFillBotsVote)
            _FillBotsVoteOverlay(session: session),
        ],
      ),
    );
  }
}

class _FillBotsVoteOverlay extends StatelessWidget {
  const _FillBotsVoteOverlay({required this.session});

  final TableSession session;

  @override
  Widget build(BuildContext context) {
    final vote = session.fillBotsVote;
    if (vote == null) {
      return const Stack(
        children: [
          ModalBarrier(color: Colors.black54, dismissible: false),
          Center(
            child: Card(
              color: Color(0xFF123C30),
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFFC857)),
                    SizedBox(height: 18),
                    Text(
                      'AGUARDANDO RESPOSTAS',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 8),
                    Text('Enviando seu pedido aos outros jogadores...'),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (vote.requesterSeatIndex != session.seatIndex &&
        vote.participantSeatIndexes.contains(session.seatIndex) &&
        vote.shownAtFor(session.seatIndex) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) session.reportFillBotsVoteShown(vote.id);
      });
    }

    final requester = vote.requesterSeatIndex >= 0 &&
            vote.requesterSeatIndex < session.seats.length
        ? session.seats[vote.requesterSeatIndex]
        : null;
    final isRequester = vote.requesterSeatIndex == session.seatIndex;
    final localVote = vote.voteFor(session.seatIndex);
    final canRespond = session.canRespondToFillBotsVote;
    final responders = vote.participantSeatIndexes
        .where((index) => index != vote.requesterSeatIndex)
        .toList(growable: false);
    final accepted =
        responders.where((index) => vote.voteFor(index) == true).length;
    final refused =
        responders.where((index) => vote.voteFor(index) == false).length;
    final pending = responders.length - accepted - refused;
    final expiresAt = vote.expiresAt;
    final remainingMs = expiresAt == null
        ? 10000
        : expiresAt.difference(DateTime.now()).inMilliseconds.clamp(0, 10000);
    final remainingSeconds = (remainingMs / 1000).ceil();

    String message;
    if (expiresAt == null && isRequester) {
      message =
          'Pedido enviado. O tempo começará somente depois que a mensagem aparecer para todos os outros jogadores.';
    } else if (expiresAt == null && canRespond == false && localVote == null) {
      message =
          '${requester?.name ?? 'Outro jogador'} pediu para completar a mesa com robôs. Preparando o tempo de resposta...';
    } else if (isRequester) {
      message =
          'Você pediu para completar a mesa com robôs. Aguardando a resposta dos outros jogadores.';
    } else if (canRespond) {
      message =
          '${requester?.name ?? 'Outro jogador'} pediu para completar a mesa com robôs. Você aceita?';
    } else if (localVote != null) {
      message = 'Sua resposta foi enviada. Aguardando os demais jogadores.';
    } else {
      message =
          '${requester?.name ?? 'Outro jogador'} pediu para completar a mesa com robôs. Aguardando a decisão dos jogadores que já estavam na mesa.';
    }

    return Stack(
      key: const ValueKey('dialogo-votacao-robos'),
      children: [
        const ModalBarrier(color: Colors.black54, dismissible: false),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: const Color(0xFF123C30),
                  elevation: 18,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.smart_toy_rounded,
                          color: Color(0xFFFFC857),
                          size: 44,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isRequester || !canRespond
                              ? 'AGUARDANDO RESPOSTAS'
                              : 'COMPLETAR COM ROBÔS?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFD46B),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final index in vote.participantSeatIndexes)
                              _FillBotsVotePlayer(
                                seat: index >= 0 && index < session.seats.length
                                    ? session.seats[index]
                                    : null,
                                status: index == vote.requesterSeatIndex
                                    ? _FillBotsVoteStatus.requester
                                    : vote.voteFor(index) == true
                                        ? _FillBotsVoteStatus.accepted
                                        : vote.voteFor(index) == false
                                            ? _FillBotsVoteStatus.refused
                                            : _FillBotsVoteStatus.pending,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$accepted aceitaram  •  $refused recusaram  •  $pending aguardando',
                          key: const ValueKey('resumo-votacao-robos'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          key: const ValueKey('tempo-votacao-robos'),
                          value: expiresAt == null ? null : remainingMs / 10000,
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(4),
                          color: const Color(0xFFFFC857),
                          backgroundColor: Colors.white12,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          expiresAt == null
                              ? 'O tempo de resposta ainda não começou'
                              : '$remainingSeconds ${remainingSeconds == 1 ? 'segundo' : 'segundos'} para responder',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                            fontSize: 12,
                          ),
                        ),
                        if (canRespond) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey('recusar-robos'),
                                  onPressed: session.submittingFillBotsVote
                                      ? null
                                      : () =>
                                          session.respondToFillBotsVote(false),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('NÃO ACEITO'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFF9E80),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  key: const ValueKey('aceitar-robos'),
                                  onPressed: session.submittingFillBotsVote
                                      ? null
                                      : () =>
                                          session.respondToFillBotsVote(true),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('ACEITO'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _FillBotsVoteStatus { requester, accepted, refused, pending }

class _FillBotsVotePlayer extends StatelessWidget {
  const _FillBotsVotePlayer({required this.seat, required this.status});

  final LobbySeat? seat;
  final _FillBotsVoteStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      _FillBotsVoteStatus.requester => (
          const Color(0xFFFFC857),
          Icons.smart_toy_rounded,
          'Pediu'
        ),
      _FillBotsVoteStatus.accepted => (
          const Color(0xFF67D391),
          Icons.check_rounded,
          'Aceitou'
        ),
      _FillBotsVoteStatus.refused => (
          const Color(0xFFFF7D6E),
          Icons.close_rounded,
          'Recusou'
        ),
      _FillBotsVoteStatus.pending => (
          Colors.blueGrey,
          Icons.hourglass_top_rounded,
          'Aguardando'
        ),
    };
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _TablePlayerAvatar(
                isBot: false,
                photoUrl: seat?.photoUrl,
                color: color,
                radius: 24,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: color,
                  child: Icon(icon, color: const Color(0xFF123C30), size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            seat?.name ?? 'Jogador',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          Text(label, style: TextStyle(color: color, fontSize: 9)),
        ],
      ),
    );
  }
}

class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({
    required this.game,
    required this.tableSession,
    required this.leaving,
    required this.onLeave,
  });

  final DouradinhaGame game;
  final TableSession tableSession;
  final bool leaving;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    if (phone) {
      return Container(
        key: const ValueKey('cabecalho-mesa-mobile'),
        height: 72,
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 5),
        decoration: const BoxDecoration(
          color: Color(0xFF052D22),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _TeamScore(
                    label: game.teamOneLabel,
                    score: game.scores[0],
                    color: const Color(0xFF5CB6FF),
                    compact: true,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('×',
                        style: TextStyle(fontSize: 18, color: Colors.white54)),
                  ),
                  _TeamScore(
                    label: game.teamTwoLabel,
                    score: game.scores[1],
                    color: const Color(0xFFFFC857),
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _HandWinnerDots(
                          game: game,
                          results: game.trickWinners,
                          compact: true,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${game.displayedHandNumber}ª • Vale ${DouradinhaGame.spokenValueForPoints(game.handValue)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: tableSession.errorMessage ??
                        tableSession.connectionLabel,
                    child: Icon(
                      tableSession.connected
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      size: 16,
                      color: tableSession.connected
                          ? const Color(0xFF7CE0A3)
                          : Colors.white54,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sair-da-mesa'),
                    tooltip: 'Sair da mesa',
                    visualDensity: VisualDensity.compact,
                    onPressed: leaving ? null : onLeave,
                    color: const Color(0xFFFF9E80),
                    icon: leaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                game.statusMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
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
                    _HandWinnerDots(game: game, results: game.trickWinners),
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
          const SizedBox(width: 6),
          IconButton(
            key: const ValueKey('sair-da-mesa'),
            tooltip: 'Sair da mesa',
            onPressed: leaving ? null : onLeave,
            color: const Color(0xFFFF9E80),
            icon: leaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}

class _HandWinnerDots extends StatelessWidget {
  const _HandWinnerDots({
    required this.game,
    required this.results,
    this.compact = false,
  });

  final DouradinhaGame game;
  final List<int?> results;
  final bool compact;

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
                : '${index + 1}ª mão: ${game.teamLabel(winner)}';
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
                width: compact ? 12 : 15,
                height: compact ? 12 : 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: wasPlayed ? Colors.white54 : Colors.white24,
                  ),
                ),
                child: wasPlayed && winner == null
                    ? Text(
                        '=',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 8 : 10,
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
      {required this.label,
      required this.score,
      required this.color,
      this.compact = false});

  final String label;
  final int score;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: compact ? 6 : 9,
          height: compact ? 30 : 38,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        ),
        SizedBox(width: compact ? 5 : 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: color, fontSize: compact ? 10 : 12)),
            Text('$score',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 21 : 26,
                    height: 1)),
          ],
        ),
      ],
    );
  }
}

class _TablePlayerAvatar extends StatelessWidget {
  const _TablePlayerAvatar({
    super.key,
    required this.isBot,
    required this.photoUrl,
    required this.color,
    required this.radius,
  });

  final bool isBot;
  final String? photoUrl;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
      color: const Color(0xFF052D22),
      size: radius * 1.15,
    );
    final validPhoto = photoUrl?.trim().isNotEmpty ?? false;
    final assetPath = isBot ? photoUrl : humanAvatarAssetFromPhotoUrl(photoUrl);
    return SizedBox.square(
      dimension: radius * 2,
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: ColoredBox(
          color: color,
          child: validPhoto
              ? assetPath != null
                  ? Transform.scale(
                      scale: isBot ? 1 : 1.08,
                      child: Image.asset(
                        assetPath,
                        width: radius * 2,
                        height: radius * 2,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback,
                      ),
                    )
                  : Image.network(
                      photoUrl!,
                      width: radius * 2,
                      height: radius * 2,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    )
              : fallback,
        ),
      ),
    );
  }
}

class _TurnAvatarHighlight extends StatelessWidget {
  const _TurnAvatarHighlight({
    super.key,
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.08 : 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: .7),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? color : Colors.transparent,
            width: active ? 3 : 0,
          ),
        ),
        child: child,
      ),
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
    final reveal =
        game.canHumanSeePartnerCardsInTenHand && player.team == game.humanTeam;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 2 : 6,
      ),
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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TablePlayerAvatar(
                key: ValueKey('avatar-jogador-$playerIndex'),
                isBot: !player.isHuman,
                photoUrl: player.photoUrl,
                color: teamColor,
                radius: compact ? 14 : 22,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 66 : 90),
                    child: Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: teamColor,
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 10 : 12,
                      ),
                    ),
                  ),
                  if (game.footIndex == playerIndex)
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text('PÉ',
                          style: TextStyle(color: Colors.white60, fontSize: 9)),
                    ),
                ],
              ),
            ],
          ),
          if (clockActive) ...[
            const SizedBox(height: 4),
            _TurnProgress(
              progress: turnProgress,
              secondsLeft: secondsLeft,
              width: compact ? 66 : 94,
            ),
          ],
          if (!compact || reveal) ...[
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
    final width = compact ? 38.0 : 60.0;
    final height = compact ? 56.0 : 88.0;
    final resultIsVisible =
        game.awaitingNextTrick || game.phase == MatchPhase.handFinished;
    final greatestStrength =
        game.currentTrick.where((play) => !play.hidden).fold<int>(
              0,
              (greatest, play) =>
                  play.card.strength > greatest ? play.card.strength : greatest,
            );
    final isGreatestCard = resultIsVisible &&
        !playedCard.hidden &&
        playedCard.card.strength == greatestStrength;

    return _WinningCardPulse(
      key: ValueKey(
        '${playedCard.card.code}-${playedCard.hidden}-$playerIndex',
      ),
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
        child: playedCard.hidden
            ? KeyedSubtree(
                key: ValueKey('carta-jogada-escondida-$playerIndex'),
                child: _CardBack(width: width, height: height),
              )
            : _CardFace(card: playedCard.card, width: width, height: height),
      ),
    );
  }
}

class _ChallengeCallGif extends StatelessWidget {
  const _ChallengeCallGif({
    super.key,
    required this.requestedValue,
    required this.compact,
  });

  final int requestedValue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final asset = DouradinhaGame.challengeGifAssetForPoints(requestedValue)!;
    final label = DouradinhaGame.challengeLabelForPoints(requestedValue);
    return Semantics(
      label: label,
      image: true,
      child: Image.asset(
        asset,
        key: ValueKey('imagem-gif-desafio-$requestedValue'),
        width: compact ? 88 : 132,
        height: compact ? 88 : 132,
        fit: BoxFit.contain,
        gaplessPlayback: false,
        filterQuality: FilterQuality.medium,
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
    final human = game.players[game.humanPlayerIndex];
    final active = game.isHumanTurn;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final teamColor =
        human.team == 0 ? const Color(0xFF5CB6FF) : const Color(0xFFFFC857);
    if (phone) {
      return Container(
        height: 154,
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
        decoration: const BoxDecoration(
          color: Color(0xFF052D22),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 34,
                    decoration: BoxDecoration(
                      color: active ? teamColor : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _TurnAvatarHighlight(
                    key: const ValueKey('animacao-turno-jogador-local'),
                    active: active,
                    color: teamColor,
                    child: _TablePlayerAvatar(
                      key: const ValueKey('avatar-jogador-local'),
                      isBot: false,
                      photoUrl: human.photoUrl,
                      color: teamColor,
                      radius: 17,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          human.name,
                          key: const ValueKey('nome-jogador-local'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: teamColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (clockActive)
                          _TurnProgress(
                            progress: turnProgress,
                            secondsLeft: secondsLeft,
                            width: 105,
                          )
                        else
                          Text(
                            active ? 'Sua vez' : 'Aguarde',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 116,
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: game.canHumanChallenge
                          ? game.requestHumanChallenge
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE9A23B),
                        foregroundColor: const Color(0xFF271500),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      icon: const Icon(Icons.campaign, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          game.challengeButtonLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final card in human.hand)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _PlayableCard(
                        card: card,
                        enabled: active,
                        hidden: game.isHumanCardHidden(card),
                        canToggleHidden: game.canHumanHideCard(card),
                        compact: true,
                        onTap: () => game.playHumanCard(card),
                        onToggleHidden: () => game.toggleHumanCardHidden(card),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
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
              color: active ? teamColor : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TurnAvatarHighlight(
                  key: const ValueKey('animacao-turno-jogador-local'),
                  active: active,
                  color: teamColor,
                  child: _TablePlayerAvatar(
                    key: const ValueKey('avatar-jogador-local'),
                    isBot: false,
                    photoUrl: human.photoUrl,
                    color: teamColor,
                    radius: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  human.name,
                  key: const ValueKey('nome-jogador-local'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: teamColor, fontWeight: FontWeight.bold),
                ),
                if (clockActive)
                  _TurnProgress(
                    progress: turnProgress,
                    secondsLeft: secondsLeft,
                    width: 105,
                  )
                else
                  Text(
                    active ? 'Sua vez' : 'Aguarde',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                if (game.footIndex == game.humanPlayerIndex)
                  const Text('PÉ',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
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
                      hidden: game.isHumanCardHidden(card),
                      canToggleHidden: game.canHumanHideCard(card),
                      onTap: () => game.playHumanCard(card),
                      onToggleHidden: () => game.toggleHumanCardHidden(card),
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
  const _PlayableCard({
    required this.card,
    required this.enabled,
    required this.hidden,
    required this.canToggleHidden,
    required this.onTap,
    required this.onToggleHidden,
    this.compact = false,
  });

  final PlayingCard card;
  final bool enabled;
  final bool hidden;
  final bool canToggleHidden;
  final VoidCallback onTap;
  final VoidCallback onToggleHidden;
  final bool compact;

  @override
  State<_PlayableCard> createState() => _PlayableCardState();
}

class _PlayableCardState extends State<_PlayableCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final width = widget.compact ? 58.0 : 67.0;
    final height = widget.compact ? 85.0 : 98.0;
    final buttonHeight = widget.compact ? 17.0 : 20.0;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: hovered && widget.enabled ? 1.08 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : .68,
          duration: const Duration(milliseconds: 180),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.enabled ? widget.onTap : null,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, animation) {
                        final turn = Tween<double>(begin: math.pi / 2, end: 0)
                            .animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ));
                        return AnimatedBuilder(
                          animation: turn,
                          child: child,
                          builder: (context, child) => Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(turn.value),
                            child: child,
                          ),
                        );
                      },
                      child: widget.hidden
                          ? KeyedSubtree(
                              key: const ValueKey('carta-escondida'),
                              child: _CardBack(width: width, height: height),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('carta-visivel'),
                              child: _CardFace(
                                card: widget.card,
                                width: width,
                                height: height,
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  left: 2,
                  right: 2,
                  bottom: 2,
                  height: buttonHeight,
                  child: Tooltip(
                    message: widget.canToggleHidden
                        ? widget.hidden
                            ? 'Mostrar carta'
                            : 'Jogar esta carta escondida'
                        : 'Não é possível esconder esta carta',
                    child: Material(
                      color: widget.canToggleHidden
                          ? const Color(0xE60B2D25)
                          : const Color(0xB3555555),
                      borderRadius: BorderRadius.circular(3),
                      child: InkWell(
                        key: ValueKey('esconder-carta-${widget.card.code}'),
                        onTap: widget.canToggleHidden
                            ? widget.onToggleHidden
                            : null,
                        borderRadius: BorderRadius.circular(3),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.hidden
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: widget.compact ? 9 : 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.hidden ? 'MOSTRAR' : 'ESCONDER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: widget.compact ? 6.5 : 7.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
  const _ChallengeOverlay({
    required this.game,
    required this.tableSession,
  });

  final DouradinhaGame game;
  final TableSession tableSession;

  @override
  Widget build(BuildContext context) {
    final challenge = game.pendingChallenge!;
    final online = tableSession.enabled;
    final vote = tableSession.challengeVote;
    final localVote = tableSession.localChallengeVote;
    final canRespond = !online || tableSession.canRespondToChallengeVote;

    void respond(ChallengeVoteChoice choice) {
      if (online) {
        tableSession.respondToChallengeVote(choice);
        return;
      }
      switch (choice) {
        case ChallengeVoteChoice.accept:
          game.acceptHumanChallenge();
        case ChallengeVoteChoice.fold:
          game.foldHumanChallenge();
        case ChallengeVoteChoice.raise:
          game.raiseHumanChallenge();
      }
    }

    String instructions() {
      if (!online) return 'Eles desafiaram o seu trio.';
      if (tableSession.challengeVotingVersion < 1) {
        return 'O servidor da mesa precisa ser atualizado para receber a decisão do trio.';
      }
      if (vote == null) return 'Sincronizando a decisão do trio...';
      if (localVote == ChallengeVoteChoice.fold) {
        return 'Você correu. Aguardando os outros humanos do trio.';
      }
      return 'Um aceite ou aumento decide. Sem isso, o trio corre ao fim do tempo.';
    }

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Card(
            color: const Color(0xFF123C30),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.campaign,
                      color: Color(0xFFFFC857), size: 36),
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
                  Text(
                    instructions(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (online && vote != null) ...[
                    const SizedBox(height: 10),
                    _ChallengeResponseCountdown(vote: vote),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final seatIndex in vote.participantSeatIndexes)
                          _ChallengeVoteStatus(
                            seat: seatIndex >= 0 &&
                                    seatIndex < tableSession.seats.length
                                ? tableSession.seats[seatIndex]
                                : null,
                            choice: vote.voteFor(seatIndex),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                          key: const ValueKey('correr-desafio'),
                          onPressed: canRespond
                              ? () => respond(ChallengeVoteChoice.fold)
                              : null,
                          child: const Text('CORRER')),
                      FilledButton(
                          key: const ValueKey('aceitar-desafio'),
                          onPressed: canRespond
                              ? () => respond(ChallengeVoteChoice.accept)
                              : null,
                          child: const Text('ACEITAR')),
                      if (challenge.requestedValue < 6) ...[
                        FilledButton.tonal(
                          key: const ValueKey('aumentar-desafio'),
                          onPressed: canRespond
                              ? () => respond(ChallengeVoteChoice.raise)
                              : null,
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
      ),
    );
  }
}

class _ChallengeResponseCountdown extends StatelessWidget {
  const _ChallengeResponseCountdown({required this.vote});

  final TeamChallengeVote vote;

  @override
  Widget build(BuildContext context) {
    final remaining = vote.expiresAt.difference(DateTime.now());
    final remainingMs = remaining.inMilliseconds.clamp(
      0,
      TeamChallengeVote.responseTimeout.inMilliseconds,
    );
    final initialProgress =
        remainingMs / TeamChallengeVote.responseTimeout.inMilliseconds;
    return SizedBox(
      width: 230,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('challenge-countdown-${vote.id}'),
        tween: Tween(begin: initialProgress, end: 0),
        duration: Duration(milliseconds: remainingMs),
        builder: (context, progress, child) {
          final seconds =
              (progress * TeamChallengeVote.responseTimeout.inSeconds).ceil();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$seconds s para responder',
                key: const ValueKey('tempo-resposta-desafio'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFFFFC857),
                backgroundColor: Colors.white12,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChallengeVoteStatus extends StatelessWidget {
  const _ChallengeVoteStatus({required this.seat, required this.choice});

  final LobbySeat? seat;
  final ChallengeVoteChoice? choice;

  @override
  Widget build(BuildContext context) {
    final color = switch (choice) {
      ChallengeVoteChoice.accept => const Color(0xFF63E6A5),
      ChallengeVoteChoice.fold => const Color(0xFFFF6B6B),
      ChallengeVoteChoice.raise => const Color(0xFFFFC857),
      null => Colors.white54,
    };
    final label = switch (choice) {
      ChallengeVoteChoice.accept => 'Aceitou',
      ChallengeVoteChoice.fold => 'Correu',
      ChallengeVoteChoice.raise => 'Aumentou',
      null => 'Aguardando',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TablePlayerAvatar(
            isBot: false,
            photoUrl: seat?.photoUrl,
            color: color,
            radius: 11,
          ),
          const SizedBox(width: 5),
          Text(
            '${seat?.name ?? 'Jogador'} • $label',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
                  Image.asset(
                    accepted
                        ? 'assets/images/challenge/aceito.png'
                        : 'assets/images/challenge/correu.png',
                    key: ValueKey(
                      accepted
                          ? 'imagem-desafio-aceito'
                          : 'imagem-desafio-correu',
                    ),
                    width: 210,
                    height: 210,
                    fit: BoxFit.contain,
                    semanticLabel: accepted ? 'Desafio aceito' : 'Trio correu',
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
                      'Nós vencemos a disputa.',
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
    final phone = MediaQuery.sizeOf(context).width < 600;
    return ColoredBox(
      color: Colors.black.withValues(alpha: phone ? .24 : .54),
      child: Align(
        alignment: phone ? Alignment.bottomCenter : Alignment.center,
        child: Padding(
          padding:
              phone ? const EdgeInsets.fromLTRB(8, 8, 8, 6) : EdgeInsets.zero,
          child: Card(
            key: const ValueKey('decisao-mao-de-dez'),
            margin: EdgeInsets.zero,
            color: const Color(0xFF123C30),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: phone ? 350 : 520),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? 10 : 18,
                  vertical: phone ? 8 : 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MÃO DE DEZ',
                      style: TextStyle(
                        color: const Color(0xFFFFC857),
                        fontSize: phone ? 17 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: phone ? 2 : 6),
                    Text(
                      phone
                          ? 'Veja as cartas dos parceiros • vale 4, sem Truco.'
                          : 'As cartas dos parceiros estão abertas para consulta.\nSem Truco ou aumentos; jogando, a mão vale 4.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: phone ? 11 : 14,
                      ),
                    ),
                    SizedBox(height: phone ? 6 : 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: phone ? 6 : 10,
                      runSpacing: phone ? 4 : 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('correr-mao-de-dez'),
                          style: phone
                              ? OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                )
                              : null,
                          onPressed: game.foldHumanTenHand,
                          child: Text(phone ? 'CORRER (2)' : 'CORRER (CEDE 2)'),
                        ),
                        FilledButton(
                          key: const ValueKey('jogar-mao-de-dez'),
                          style: phone
                              ? FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                )
                              : null,
                          onPressed: game.chooseToPlayTenHand,
                          child: Text(phone ? 'JOGAR' : 'JOGAR A MÃO'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
    this.duration = const Duration(seconds: 5),
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
  const _WinnerOverlay({
    required this.game,
    required this.automaticReturn,
    required this.onPlayAgain,
  });

  final DouradinhaGame game;
  final bool automaticReturn;
  final VoidCallback? onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final humanWon = game.matchWinner == game.humanTeam;
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
              humanWon ? 'SEU TRIO VENCEU!' : 'O TRIO ADVERSÁRIO VENCEU',
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
            if (automaticReturn) ...[
              const Text(
                'Removendo os robôs e voltando para a sala de espera...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              const SizedBox(
                width: 260,
                child: HandResultProgress(color: Color(0xFFFFC857)),
              ),
            ] else
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
