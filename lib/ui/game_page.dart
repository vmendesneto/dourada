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
  bool _automationScheduled = false;
  String? _scheduledChallengeNotice;
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
                    playedCard((game.humanPlayerIndex + 2) % 6,
                        const Alignment(-.58, -.46)),
                    playedCard((game.humanPlayerIndex + 3) % 6,
                        const Alignment(0, -.62)),
                    playedCard((game.humanPlayerIndex + 4) % 6,
                        const Alignment(.58, -.46)),
                    playedCard((game.humanPlayerIndex + 1) % 6,
                        const Alignment(-.58, .46)),
                    playedCard((game.humanPlayerIndex + 5) % 6,
                        const Alignment(.58, .46)),
                    playedCard(game.humanPlayerIndex, const Alignment(0, .62)),
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
      if (mounted && session.waitingStartAt != null) setState(() {});
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
      body: SafeArea(
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
                  border: Border.all(color: const Color(0xFFD7A84C), width: 2),
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
                                    color: Colors.white.withValues(alpha: .05),
                                    border: Border.all(color: Colors.white24),
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
                                style: TextStyle(color: color, fontSize: 11),
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
                          color: const Color(0xFFFFC857).withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFC857)),
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
                        onPressed:
                            session.connecting || session.missingPlayers == 0
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
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: .55)),
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
        height: 98,
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
                  const Spacer(),
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
            Row(
              children: [
                _HandWinnerDots(game: game, results: game.trickWinners),
                const SizedBox(width: 7),
                Text(
                  '${game.displayedHandNumber}ª Mão • Vale ${DouradinhaGame.spokenValueForPoints(game.handValue)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 2),
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
  const _HandWinnerDots({required this.game, required this.results});

  final DouradinhaGame game;
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
                  _TablePlayerAvatar(
                    key: const ValueKey('avatar-jogador-local'),
                    isBot: false,
                    photoUrl: human.photoUrl,
                    color: teamColor,
                    radius: 17,
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
                _TablePlayerAvatar(
                  key: const ValueKey('avatar-jogador-local'),
                  isBot: false,
                  photoUrl: human.photoUrl,
                  color: teamColor,
                  radius: 22,
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
                const Text('Eles desafiaram o seu trio.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                        onPressed: game.foldHumanChallenge,
                        child: const Text('CORRER')),
                    FilledButton(
                        onPressed: game.acceptHumanChallenge,
                        child: const Text('ACEITAR')),
                    if (challenge.requestedValue < 6) ...[
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
                    accepted ? 'DESAFIO ACEITO' : 'ELES CORRERAM',
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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: game.foldHumanTenHand,
                      child: const Text('CORRER (CEDE 2)'),
                    ),
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
    final nextMessage = game.matchWinner != null
        ? 'Resultado em 5 segundos…'
        : contestEnded
            ? 'Nova disputa em 5 segundos…'
            : 'Próxima mão em 5 segundos…';
    final disputeSummary = game.lastHandWinner == null
        ? 'Três mãos empatadas: nenhum tento.'
        : game.teamScored(game.lastHandWinner!, game.lastHandPoints);
    final strongestPlays = <PlayedCard>[];
    final visiblePlays =
        game.currentTrick.where((play) => !play.hidden).toList();
    if (visiblePlays.isNotEmpty) {
      final greatestStrength = visiblePlays.fold<int>(
        0,
        (greatest, play) =>
            play.card.strength > greatest ? play.card.strength : greatest,
      );
      strongestPlays.addAll(
        visiblePlays.where(
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
        ? '${game.teamWon(resultTeam!, 'a disputa')}!'
        : winnerTeam == null
            ? 'A mão empatou com cartas de mesma força'
            : '${game.teamWon(winnerTeam, 'a mão')} com '
                '${featuredCards.first.isManilha ? featuredCards.first.displayName : featuredCards.first.rankName}';

    final phone = MediaQuery.sizeOf(context).width < 600;
    if (phone) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: Card(
            margin: EdgeInsets.zero,
            color: const Color(0xF5123C30),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (featuredCards.isEmpty)
                    Icon(Icons.emoji_events, color: teamColor, size: 30)
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final card in featuredCards)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: teamColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: _CardFace(
                                card: card,
                                width: 32,
                                height: 47,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                completedHand > 0
                                    ? '$completedHandª MÃO'
                                    : 'FIM DA DISPUTA',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            Text(
                              'Vale ${DouradinhaGame.spokenValueForPoints(game.handValue)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          resultMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: teamColor,
                            fontSize: 14,
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
                              fontSize: 9,
                            ),
                          ),
                        const SizedBox(height: 4),
                        HandResultProgress(
                          key: ValueKey(
                            'resultado-${game.playedCards.length}-$completedHand-${game.phase.name}',
                          ),
                          color: teamColor,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nextMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
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
