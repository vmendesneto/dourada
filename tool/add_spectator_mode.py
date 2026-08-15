from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'Trecho não encontrado em {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1))


# Lobby service: entrada de espectador sem ocupar cadeira.
path = 'lib/online/lobby_service.dart'
replace_once(path,
'''  bool get canJoin =>
      phase != LobbyTablePhase.playing && playerCount < capacity;
''',
'''  bool get canJoin =>
      phase != LobbyTablePhase.playing && playerCount < capacity;
  bool get canWatch => phase == LobbyTablePhase.playing;
''')
replace_once(path,
'''    this.challengeVote,
    this.gameState,
  });
''',
'''    this.challengeVote,
    this.gameState,
    this.spectator = false,
    this.spectatorCount = 0,
  });
''')
replace_once(path,
'''  final TeamChallengeVote? challengeVote;
  final Object? gameState;
''',
'''  final TeamChallengeVote? challengeVote;
  final Object? gameState;
  final bool spectator;
  final int spectatorCount;
''')
replace_once(path,
'''        challengeVote: TeamChallengeVote.fromJsonValue(json['challengeVote']),
        gameState: json['gameState'],
      );
''',
'''        challengeVote: TeamChallengeVote.fromJsonValue(json['challengeVote']),
        gameState: json['gameState'],
        spectator: json['spectator'] as bool? ?? false,
        spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
      );
''')
replace_once(path,
'''  Future<SavedTableSession?> savedSession() async {
''',
'''  Future<TableEntry> watchTable(int tableNumber) async {
    if (!enabled) {
      throw StateError('Só é possível assistir partidas online.');
    }
    final response = await _client
        .post(
          Uri.parse('$serverUrl/api/tables/$tableNumber/watch'),
          headers: const {'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 12));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(
        payload['error'] as String? ?? 'Não foi possível assistir à partida.',
      );
    }
    final entry = TableEntry.fromJson(serverUrl, payload);
    if (!entry.spectator || entry.phase != LobbyTablePhase.playing) {
      throw StateError('Esta partida não está disponível para assistir.');
    }
    return entry;
  }

  Future<SavedTableSession?> savedSession() async {
''')


# TableSession: websocket somente leitura, reconexão e contador de espectadores.
path = 'lib/online/table_session.dart'
replace_once(path,
'''      challengeVote = entry!.challengeVote;
    }
''',
'''      challengeVote = entry!.challengeVote;
      spectatorCount = entry!.spectatorCount;
    }
''')
replace_once(path,
'''  bool replacementBotActive = false;
  bool seatUnavailable = false;
  String? _reportedShownFillBotsVoteId;

  bool get enabled => _serverUrl.isNotEmpty && entry?.online != false;
''',
'''  bool replacementBotActive = false;
  bool seatUnavailable = false;
  bool spectatorMatchEnded = false;
  int spectatorCount = 0;
  String? _reportedShownFillBotsVoteId;

  bool get enabled => _serverUrl.isNotEmpty && entry?.online != false;
  bool get isSpectator => entry?.spectator == true;
''')
replace_once(path,
'''  bool get waiting => enabled && phase == LobbyTablePhase.waiting;
  bool get canPlayHere =>
      !enabled || (connected && phase == LobbyTablePhase.playing);
''',
'''  bool get waiting =>
      !isSpectator && enabled && phase == LobbyTablePhase.waiting;
  bool get canPlayHere => isSpectator
      ? (!enabled ||
          (connected &&
              phase == LobbyTablePhase.playing &&
              !spectatorMatchEnded))
      : (!enabled || (connected && phase == LobbyTablePhase.playing));
''')
replace_once(path,
'''    return vote != null &&
''',
'''    return !isSpectator &&
        vote != null &&
''')
replace_once(path,
'''    return enabled &&
        challengeVotingVersion >= 1 &&
''',
'''    return !isSpectator &&
        enabled &&
        challengeVotingVersion >= 1 &&
''')
replace_once(path,
'''  String get connectionLabel {
    if (!enabled) return 'Mesa local';
''',
'''  String get connectionLabel {
    if (isSpectator) {
      if (connecting) return 'Conectando para assistir...';
      if (connected) return 'Assistindo mesa $tableNumber';
      return 'Transmissão da mesa $tableNumber';
    }
    if (!enabled) return 'Mesa local';
''')
replace_once(path,
'''  Future<void> leaveTable() async {
    if (_disposed) return;
''',
'''  Future<void> leaveTable() async {
    if (_disposed) return;
    if (isSpectator) {
      _presencePaused = true;
      _reconnectTimer?.cancel();
      connected = false;
      spectatorMatchEnded = false;
      playerToken = null;
      websocketUrl = null;
      unawaited(_closeChannel());
      if (!_disposed) notifyListeners();
      return;
    }
''')
replace_once(path,
'''  void syncGame(DouradinhaGame game) {
    if (_applyingRemoteState || !canPlayHere || _channel == null) {
''',
'''  void syncGame(DouradinhaGame game) {
    if (isSpectator ||
        _applyingRemoteState ||
        !canPlayHere ||
        _channel == null) {
''')
replace_once(path,
'''    challengeVote = value.challengeVote;
    _configureSeats();
''',
'''    challengeVote = value.challengeVote;
    spectatorCount = value.spectatorCount;
    _configureSeats();
''')
replace_once(path,
'''    challengeVote = TeamChallengeVote.fromJsonValue(payload['challengeVote']);
    if (fillBotsVote?.id != _reportedShownFillBotsVoteId) {
''',
'''    challengeVote = TeamChallengeVote.fromJsonValue(payload['challengeVote']);
    spectatorCount = (payload['spectatorCount'] as num?)?.toInt() ?? 0;
    final gameState = payload['gameState'];
    if (isSpectator &&
        (phase != LobbyTablePhase.playing ||
            (gameState is Map && gameState['phase'] == 'gameOver'))) {
      spectatorMatchEnded = true;
      _presencePaused = true;
      _reconnectTimer?.cancel();
    }
    if (fillBotsVote?.id != _reportedShownFillBotsVoteId) {
''')
replace_once(path,
'''    _restoreRemoteState(payload['gameState']);
''',
'''    _restoreRemoteState(gameState);
''')
replace_once(path,
'''      replacementBotActive = phase == LobbyTablePhase.playing;
      errorMessage = 'Não foi possível conectar à mesa.';
''',
'''      replacementBotActive =
          !isSpectator && phase == LobbyTablePhase.playing;
      errorMessage = isSpectator
          ? 'Não foi possível conectar à transmissão.'
          : 'Não foi possível conectar à mesa.';
''')
old_rejoin = '''  Future<void> _rejoinAndConnect() async {
    if (playerToken == null || tableNumber == null) return;
    try {
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/tables/$tableNumber/join'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerToken': playerToken}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 401 || response.statusCode == 403) {
        connected = false;
        seatUnavailable = true;
        _presencePaused = true;
        _reconnectTimer?.cancel();
        errorMessage = null;
        notifyListeners();
        return;
      }
      if (response.statusCode != 200) {
        throw StateError('Não foi possível reconectar à mesa.');
      }
      seatUnavailable = false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      websocketUrl = payload['websocketUrl'] as String;
      _applyRoomPayload(payload);
      await _connectSocket();
    } on Object {
      errorMessage = 'Não foi possível reconectar à mesa.';
      notifyListeners();
      if (!_presencePaused) _scheduleReconnect();
    }
  }
'''
new_rejoin = '''  Future<void> _rejoinAndConnect() async {
    if (tableNumber == null) return;
    try {
      if (isSpectator) {
        final response = await _client
            .post(
              Uri.parse('$_serverUrl/api/tables/$tableNumber/watch'),
              headers: const {'Content-Type': 'application/json'},
              body: '{}',
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 409 || response.statusCode == 410) {
          connected = false;
          spectatorMatchEnded = true;
          _presencePaused = true;
          _reconnectTimer?.cancel();
          errorMessage = null;
          notifyListeners();
          return;
        }
        if (response.statusCode != 200) {
          throw StateError('Não foi possível reconectar à transmissão.');
        }
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        playerToken = payload['playerToken'] as String;
        websocketUrl = payload['websocketUrl'] as String;
        _applyRoomPayload(payload);
        await _connectSocket();
        return;
      }
      if (playerToken == null) return;
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/tables/$tableNumber/join'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerToken': playerToken}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 401 || response.statusCode == 403) {
        connected = false;
        seatUnavailable = true;
        _presencePaused = true;
        _reconnectTimer?.cancel();
        errorMessage = null;
        notifyListeners();
        return;
      }
      if (response.statusCode != 200) {
        throw StateError('Não foi possível reconectar à mesa.');
      }
      seatUnavailable = false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      websocketUrl = payload['websocketUrl'] as String;
      _applyRoomPayload(payload);
      await _connectSocket();
    } on Object {
      errorMessage = isSpectator
          ? 'Não foi possível reconectar à transmissão.'
          : 'Não foi possível reconectar à mesa.';
      notifyListeners();
      if (!_presencePaused) _scheduleReconnect();
    }
  }
'''
replace_once(path, old_rejoin, new_rejoin)
replace_once(path,
'''  void _handleSocketClosed() {
    if (_disposed) return;
    connected = false;
    replacementBotActive = phase == LobbyTablePhase.playing;
    notifyListeners();
    if (!_presencePaused) _scheduleReconnect();
  }
''',
'''  void _handleSocketClosed() {
    if (_disposed) return;
    connected = false;
    replacementBotActive =
        !isSpectator && phase == LobbyTablePhase.playing;
    if (isSpectator && phase != LobbyTablePhase.playing) {
      spectatorMatchEnded = true;
      _presencePaused = true;
    }
    notifyListeners();
    if (!_presencePaused) _scheduleReconnect();
  }
''')


# GamePage: visualização sem controles/cartas e retorno automático ao lobby.
path = 'lib/ui/game_page.dart'
replace_once(path,
'''  Timer? _challengeAnimationTimer;
''',
'''  Timer? _challengeAnimationTimer;
  Timer? _spectatorReturnTimer;
''')
replace_once(path,
'''  bool _restoringGame = true;
  bool _leavingTable = false;
''',
'''  bool _restoringGame = true;
  bool _leavingTable = false;
  bool _spectatorEnding = false;
''')
replace_once(path,
'''    _challengeAnimationTimer?.cancel();
''',
'''    _challengeAnimationTimer?.cancel();
    _spectatorReturnTimer?.cancel();
''')
replace_once(path,
'''  void _onGameChanged() {
    if (!mounted) return;
    if (_restoringGame) {
''',
'''  void _onGameChanged() {
    if (!mounted) return;
    if (tableSession.isSpectator) {
      _syncChallengeAnimation();
      _syncChallengeNotice();
      setState(() {});
      return;
    }
    if (_restoringGame) {
''')
replace_once(path,
'''  Future<void> _confirmLeaveTable() async {
    if (_leavingTable) return;
''',
'''  Future<void> _leaveSpectator() async {
    if (_leavingTable || !mounted) return;
    setState(() => _leavingTable = true);
    await tableSession.leaveTable();
    await exitGameFullscreen();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmLeaveTable() async {
    if (_leavingTable) return;
    if (tableSession.isSpectator) {
      await _leaveSpectator();
      return;
    }
''')
replace_once(path,
'''  void _onTableSessionChanged() {
    if (!mounted) return;
    if (tableSession.seatUnavailable) {
''',
'''  void _onTableSessionChanged() {
    if (!mounted) return;
    if (tableSession.isSpectator && tableSession.spectatorMatchEnded) {
      _automationTimer?.cancel();
      _automationScheduled = false;
      _stopTurnClock();
      _handleSpectatorMatchEnded();
      return;
    }
    if (tableSession.seatUnavailable) {
''')
replace_once(path,
'''  Future<void> _restoreSavedGame() async {
''',
'''  void _handleSpectatorMatchEnded() {
    if (_spectatorEnding || !mounted) return;
    _spectatorEnding = true;
    _spectatorReturnTimer?.cancel();
    setState(() {});
    _spectatorReturnTimer = Timer(const Duration(seconds: 2), () async {
      await exitGameFullscreen();
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _restoreSavedGame() async {
''')
replace_once(path,
'''  void _syncTurnClock() {
    if (!mounted ||
''',
'''  void _syncTurnClock() {
    if (tableSession.isSpectator) {
      _stopTurnClock();
      return;
    }
    if (!mounted ||
''')
replace_once(path,
'''    if (!mounted ||
        _restoringGame ||
        tableSession.serverControlsAutomation ||
''',
'''    if (!mounted ||
        _restoringGame ||
        tableSession.isSpectator ||
        tableSession.serverControlsAutomation ||
''')
replace_once(path,
'''    if (tableSession.waiting ||
        (tableSession.enabled && tableSession.phase == LobbyTablePhase.empty)) {
''',
'''    if (!tableSession.isSpectator &&
        (tableSession.waiting ||
            (tableSession.enabled &&
                tableSession.phase == LobbyTablePhase.empty))) {
''')
replace_once(path,
'''            Expanded(child: _buildTable()),
            _HumanControls(
              game: game,
              clockActive: _clockPlayerIndex == game.humanPlayerIndex,
              turnProgress: _turnProgress,
              secondsLeft: _turnSecondsLeft,
            ),
''',
'''            Expanded(child: _buildTable()),
            if (!tableSession.isSpectator)
              _HumanControls(
                game: game,
                clockActive: _clockPlayerIndex == game.humanPlayerIndex,
                turnProgress: _turnProgress,
                secondsLeft: _turnSecondsLeft,
              ),
''')
replace_once(path,
'''      builder: (context, constraints) {
        final phone = MediaQuery.sizeOf(context).width < 600;
''',
'''      builder: (context, constraints) {
        final spectator = tableSession.isSpectator;
        final phone = MediaQuery.sizeOf(context).width < 600;
''')
replace_once(path,
'''                  secondsLeft: _turnSecondsLeft,
                ),
''',
'''                  secondsLeft: _turnSecondsLeft,
                  spectatorMode: spectator,
                ),
''')
replace_once(path,
'''                    botSeat((game.humanPlayerIndex + 5) % 6,
                        Alignment(sideSeatX, .52)),
                    for (final entry in playedCardAlignments.entries)
''',
'''                    botSeat((game.humanPlayerIndex + 5) % 6,
                        Alignment(sideSeatX, .52)),
                    if (spectator)
                      botSeat(game.humanPlayerIndex, const Alignment(0, 1)),
                    for (final entry in playedCardAlignments.entries)
''')
replace_once(path,
'''            Positioned(
              right: phone ? 6 : 18,
              bottom: phone ? 2 : 8,
              child: const _ManilhasButton(),
            ),
            if (game.humanMustAnswerChallenge)
''',
'''            if (!spectator)
              Positioned(
                right: phone ? 6 : 18,
                bottom: phone ? 2 : 8,
                child: const _ManilhasButton(),
              ),
            if (!spectator && game.humanMustAnswerChallenge)
''')
replace_once(path,
'''            if (game.humanTenDecisionPending)
              Positioned.fill(child: _TenHandOverlay(game: game)),
''',
'''            if (!spectator && game.humanTenDecisionPending)
              Positioned.fill(child: _TenHandOverlay(game: game)),
''')
replace_once(path,
'''            if (game.phase == MatchPhase.gameOver)
              Positioned.fill(
''',
'''            if (!spectator && game.phase == MatchPhase.gameOver)
              Positioned.fill(
''')
replace_once(path,
'''            if (!tableSession.canPlayHere)
              Positioned.fill(
                child: _ReconnectingOverlay(tableSession: tableSession),
              ),
''',
'''            if (!tableSession.canPlayHere && !_spectatorEnding)
              Positioned.fill(
                child: _ReconnectingOverlay(tableSession: tableSession),
              ),
            if (_spectatorEnding)
              const Positioned.fill(child: _SpectatorEndedOverlay()),
''')
replace_once(path,
'''  const _ScoreBoard({
''',
'''  const _ScoreBoard({
''')
# Eye indicator in mobile and desktop headers.
replace_once(path,
'''                  const SizedBox(width: 4),
                  Tooltip(
                    message: tableSession.errorMessage ??
''',
'''                  if (!tableSession.isSpectator &&
                      tableSession.spectatorCount > 0) ...[
                    const SizedBox(width: 4),
                    _SpectatorIndicator(count: tableSession.spectatorCount),
                  ],
                  const SizedBox(width: 4),
                  Tooltip(
                    message: tableSession.errorMessage ??
''')
replace_once(path,
'''          const SizedBox(width: 10),
          Tooltip(
            message: tableSession.errorMessage ?? tableSession.connectionLabel,
''',
'''          if (!tableSession.isSpectator && tableSession.spectatorCount > 0) ...[
            const SizedBox(width: 8),
            _SpectatorIndicator(count: tableSession.spectatorCount),
          ],
          const SizedBox(width: 10),
          Tooltip(
            message: tableSession.errorMessage ?? tableSession.connectionLabel,
''')
replace_once(path,
'''class _HandWinnerDots extends StatelessWidget {
''',
'''class _SpectatorIndicator extends StatelessWidget {
  const _SpectatorIndicator({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: count == 1 ? '1 pessoa assistindo' : '$count pessoas assistindo',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, color: Color(0xFF8FD3FF), size: 18),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF8FD3FF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HandWinnerDots extends StatelessWidget {
''')
replace_once(path,
'''  const _BotSeat({
    required this.game,
    required this.playerIndex,
    required this.compact,
    required this.clockActive,
    required this.turnProgress,
    required this.secondsLeft,
  });
''',
'''  const _BotSeat({
    required this.game,
    required this.playerIndex,
    required this.compact,
    required this.clockActive,
    required this.turnProgress,
    required this.secondsLeft,
    this.spectatorMode = false,
  });
''')
replace_once(path,
'''  final int secondsLeft;

  @override
''',
'''  final int secondsLeft;
  final bool spectatorMode;

  @override
''')
replace_once(path,
'''          if (!compact || reveal) ...[
''',
'''          if (!spectatorMode && (!compact || reveal)) ...[
''')
replace_once(path,
'''                Text(
                  'RECONECTANDO À MESA ${tableSession.tableNumber ?? ''}',
''',
'''                Text(
                  tableSession.isSpectator
                      ? 'RECONECTANDO À PARTIDA'
                      : 'RECONECTANDO À MESA ${tableSession.tableNumber ?? ''}',
''')
replace_once(path,
'''                const Text(
                  'Um robô está jogando no seu lugar.',
                  style: TextStyle(color: Colors.white70),
                ),
''',
'''                Text(
                  tableSession.isSpectator
                      ? 'Tentando continuar a transmissão como espectador.'
                      : 'Um robô está jogando no seu lugar.',
                  style: const TextStyle(color: Colors.white70),
                ),
''')
replace_once(path,
'''class _FootLegend extends StatelessWidget {
''',
'''class _SpectatorEndedOverlay extends StatelessWidget {
  const _SpectatorEndedOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Card(
          color: const Color(0xFF123C30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_score_rounded,
                    color: Color(0xFFFFC857), size: 52),
                const SizedBox(height: 10),
                const Text(
                  'A PARTIDA ACABOU',
                  key: ValueKey('partida-acabou-espectador'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Voltando para o lobby...',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    color: Color(0xFFFFC857),
                    backgroundColor: Colors.white12,
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

class _FootLegend extends StatelessWidget {
''')


# Lobby: botão VER em partidas em andamento.
path = 'lib/ui/lobby_page.dart'
replace_once(path,
'''  Future<void> _quickEnter() async {
''',
'''  Future<void> _watch(LobbyTable table) async {
    if (_openingTable != null || table.phase != LobbyTablePhase.playing) return;
    setState(() => _openingTable = table.tableNumber);
    await enterGameFullscreen();
    final lobbySubscription = _lobbySubscription;
    _lobbySubscription = null;
    if (lobbySubscription != null) {
      unawaited(lobbySubscription.cancel());
    }
    try {
      final entry = await _service.watchTable(table.tableNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GamePage(entry: entry)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      await exitGameFullscreen();
      if (mounted) {
        setState(() => _openingTable = null);
        unawaited(_connectLobby());
      }
    }
  }

  Future<void> _quickEnter() async {
''')
replace_once(path,
'''                              onEnter: table.canJoin
                                  ? requiresLogin
                                      ? _signIn
                                      : () => _enter(table)
                                  : null,
                              firstButtonKey: index == 0
''',
'''                              onEnter: table.canJoin
                                  ? requiresLogin
                                      ? _signIn
                                      : () => _enter(table)
                                  : null,
                              onWatch: table.canWatch ? () => _watch(table) : null,
                              firstButtonKey: index == 0
''')
replace_once(path,
'''    required this.onEnter,
    this.firstButtonKey,
  });
''',
'''    required this.onEnter,
    required this.onWatch,
    this.firstButtonKey,
  });
''')
replace_once(path,
'''  final VoidCallback? onEnter;
  final Key? firstButtonKey;
''',
'''  final VoidCallback? onEnter;
  final VoidCallback? onWatch;
  final Key? firstButtonKey;
''')
replace_once(path,
'''              onPressed: opening ? null : onEnter,
''',
'''              onPressed: opening
                  ? null
                  : table.phase == LobbyTablePhase.playing
                      ? onWatch
                      : onEnter,
''')
replace_once(path,
'''                  : Text(table.phase == LobbyTablePhase.playing
                      ? 'SEM VAGA'
''',
'''                  : Text(table.phase == LobbyTablePhase.playing
                      ? 'VER'
''')


# Cloudflare Worker: conexão read-only de espectador e contador em tempo real.
path = 'cloudflare/src/index.ts'
replace_once(path,
'''interface SocketAttachment {
  token: string;
  seatIndex: number;
  connectedAt: number;
}
''',
'''interface SocketAttachment {
  role?: "player" | "spectator";
  token: string;
  seatIndex: number;
  connectedAt: number;
}
''')
replace_once(path,
'''      /^\\/api\\/tables\\/(10|[1-9])\\/(join|fill-bots|can-resume|decline-resume|leave|connect)$/,
''',
'''      /^\\/api\\/tables\\/(10|[1-9])\\/(join|watch|fill-bots|can-resume|decline-resume|leave|connect|watch-connect)$/,
''')
replace_once(path,
'''      if (operation === "connect") {
        return tableStub(env, tableNumber).fetch(request);
      }
''',
'''      if (operation === "connect" || operation === "watch-connect") {
        return tableStub(env, tableNumber).fetch(request);
      }
''')
replace_once(path,
'''          websocketUrl: connectionUrl(url, tableNumber, String(body.playerToken)),
''',
'''          websocketUrl: connectionUrl(
            url,
            tableNumber,
            String(body.playerToken),
            operation === "watch" ? "watch-connect" : "connect",
          ),
''')
replace_once(path,
'''    if (url.pathname === "/join" && request.method === "POST") {
      return this.join(request, requestedTableNumber);
    }
''',
'''    if (url.pathname === "/join" && request.method === "POST") {
      return this.join(request, requestedTableNumber);
    }
    if (url.pathname === "/watch" && request.method === "POST") {
      return this.watch(requestedTableNumber);
    }
''')
replace_once(path,
'''    if (url.pathname.match(/^\\/api\\/tables\\/(10|[1-9])\\/connect$/)) {
      return this.connectSocket(request);
    }
''',
'''    if (url.pathname.match(/^\\/api\\/tables\\/(10|[1-9])\\/connect$/)) {
      return this.connectSocket(request);
    }
    if (url.pathname.match(/^\\/api\\/tables\\/(10|[1-9])\\/watch-connect$/)) {
      return this.connectSpectatorSocket(request);
    }
''')
replace_once(path,
'''    if (!attachment || !this.validHuman(table, attachment.seatIndex, attachment.token)) {
      socket.close(4003, "Sessão inválida");
      return;
    }
''',
'''    if (!attachment) {
      socket.close(4003, "Sessão inválida");
      return;
    }
    if (attachment.role === "spectator") return;
    if (!this.validHuman(table, attachment.seatIndex, attachment.token)) {
      socket.close(4003, "Sessão inválida");
      return;
    }
''')
replace_once(path,
'''  ): Promise<void> {
    await this.markDisconnected(socket);
    socket.close(code, reason);
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    await this.markDisconnected(socket);
    socket.close(1011, "Erro de conexão");
  }
''',
'''  ): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment?.role === "spectator") {
      const table = await this.load();
      this.broadcast(table);
      socket.close(code, reason);
      return;
    }
    await this.markDisconnected(socket);
    socket.close(code, reason);
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment?.role === "spectator") {
      const table = await this.load();
      this.broadcast(table);
      socket.close(1011, "Erro de conexão");
      return;
    }
    await this.markDisconnected(socket);
    socket.close(1011, "Erro de conexão");
  }
''')
replace_once(path,
'''        this.returnToWaitingRoom(table, now);
        await this.saveAndSchedule(table, true);
        this.broadcast(table);
        return;
''',
'''        this.returnToWaitingRoom(table, now);
        await this.saveAndSchedule(table, true);
        this.broadcast(table);
        this.closeSpectators();
        return;
''')
replace_once(path,
'''      this.returnToWaitingRoom(table, Date.now());
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
      return;
''',
'''      this.returnToWaitingRoom(table, Date.now());
      await this.saveAndSchedule(table, true);
      this.broadcast(table);
      this.closeSpectators();
      return;
''')
replace_once(path,
'''  private async fillBots(request: Request, tableNumber?: number): Promise<Response> {
''',
'''  private async watch(tableNumber?: number): Promise<Response> {
    const table = await this.load(tableNumber);
    if (
      table.phase !== "playing" ||
      table.gameState === null ||
      table.gameState.phase === "gameOver"
    ) {
      return Response.json(
        { error: "Esta partida não está disponível para assistir." },
        { status: 409 },
      );
    }
    const token = crypto.randomUUID();
    return Response.json({
      tableNumber: String(table.tableNumber),
      playerToken: token,
      seatIndex: 0,
      spectator: true,
      spectatorCount: this.spectatorCount(),
      phase: table.phase,
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
      fillBotsVotingVersion: 0,
      challengeVotingVersion: 0,
      fillBotsVote: null,
      challengeVote: null,
      waitingStartAt: null,
    });
  }

  private async fillBots(request: Request, tableNumber?: number): Promise<Response> {
''')
replace_once(path,
'''    this.ctx.acceptWebSocket(server, [`seat:${seatIndex}`]);
    server.serializeAttachment({ token, seatIndex, connectedAt: Date.now() });
''',
'''    this.ctx.acceptWebSocket(server, [`seat:${seatIndex}`]);
    server.serializeAttachment({
      role: "player",
      token,
      seatIndex,
      connectedAt: Date.now(),
    });
''')
replace_once(path,
'''  private async markDisconnected(socket: WebSocket): Promise<void> {
''',
'''  private async connectSpectatorSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket obrigatório", { status: 426 });
    }
    const table = await this.load();
    if (
      table.phase !== "playing" ||
      table.gameState === null ||
      table.gameState.phase === "gameOver"
    ) {
      return new Response("Partida encerrada", { status: 409 });
    }
    const token = new URL(request.url).searchParams.get("token");
    if (!token) return new Response("Sessão inválida", { status: 403 });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [`spectator:${token}`]);
    server.serializeAttachment({
      role: "spectator",
      token,
      seatIndex: -1,
      connectedAt: Date.now(),
    });
    for (const oldSocket of this.ctx.getWebSockets(`spectator:${token}`)) {
      if (oldSocket !== server) oldSocket.close(4000, "Conexão substituída");
    }
    server.send(JSON.stringify(this.spectatorRoomMessage(table)));
    this.broadcast(table, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async markDisconnected(socket: WebSocket): Promise<void> {
''')
replace_once(path,
'''    if (!attachment) return;
''',
'''    if (!attachment || attachment.role === "spectator") return;
''')
replace_once(path,
'''      challengeVotingVersion,
      status: this.status(table),
''',
'''      challengeVotingVersion,
      spectatorCount: this.spectatorCount(),
      status: this.status(table),
''')
replace_once(path,
'''      challengeVote: table.challengeVote,
      challengeVotingVersion,
    };
  }

  private broadcast(table: SharedTableState, except?: WebSocket): void {
''',
'''      challengeVote: table.challengeVote,
      challengeVotingVersion,
      spectatorCount: this.spectatorCount(),
    };
  }

  private spectatorRoomMessage(table: SharedTableState): Record<string, unknown> {
    return {
      type: "room",
      phase: table.phase,
      tableNumber: String(table.tableNumber),
      seatIndex: 0,
      spectator: true,
      spectatorCount: this.spectatorCount(),
      seats: publicSeats(table),
      gameState: spectatorGameState(table.gameState),
      waitingStartAt: null,
      fillBotsVote: null,
      fillBotsVotingVersion: 0,
      challengeVote: null,
      challengeVotingVersion: 0,
    };
  }

  private broadcast(table: SharedTableState, except?: WebSocket): void {
''')
replace_once(path,
'''      if (!attachment) continue;
      socket.send(JSON.stringify(this.roomMessage(table, attachment.seatIndex)));
''',
'''      if (!attachment) continue;
      socket.send(JSON.stringify(
        attachment.role === "spectator"
          ? this.spectatorRoomMessage(table)
          : this.roomMessage(table, attachment.seatIndex),
      ));
''')
replace_once(path,
'''      if (!attachment) continue;
      active.add(attachment.seatIndex);
''',
'''      if (!attachment || attachment.role === "spectator") continue;
      active.add(attachment.seatIndex);
''')
replace_once(path,
'''  private refreshDisconnections(
''',
'''  private spectatorCount(): number {
    return this.ctx.getWebSockets().filter((socket) => {
      if (socket.readyState !== WebSocket.OPEN) return false;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      return attachment?.role === "spectator";
    }).length;
  }

  private closeSpectators(): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (attachment?.role === "spectator") {
        socket.close(4004, "Partida encerrada");
      }
    }
  }

  private refreshDisconnections(
''')
replace_once(path,
'''function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
''',
'''function spectatorGameState(gameState: GameState | null): GameState | null {
  if (gameState === null) return null;
  return {
    ...gameState,
    playerHands: gameState.playerHands.map(() => []),
    hiddenCards: gameState.hiddenCards.map(() => []),
  };
}

function publicSeats(table: SharedTableState): Array<Record<string, unknown> | null> {
''')
replace_once(path,
'''function connectionUrl(requestUrl: URL, tableNumber: number, token: string): string {
  const protocol = requestUrl.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${requestUrl.host}/api/tables/${tableNumber}/connect?token=${encodeURIComponent(token)}`;
}
''',
'''function connectionUrl(
  requestUrl: URL,
  tableNumber: number,
  token: string,
  operation = "connect",
): string {
  const protocol = requestUrl.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${requestUrl.host}/api/tables/${tableNumber}/${operation}?token=${encodeURIComponent(token)}`;
}
''')


# Tests: serviço watch e UI do lobby.
path = 'test/lobby_service_test.dart'
replace_once(path,
'''  test('usa nome e foto do perfil na mesa local', () async {
''',
'''  test('assiste uma partida sem salvar sessão de jogador', () async {
    SharedPreferences.setMockInitialValues({});
    late http.Request sentRequest;
    final service = LobbyService(
      serverUrl: 'https://dourada.example.workers.dev',
      client: MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'tableNumber': '4',
            'playerToken': 'token-espectador',
            'websocketUrl': 'wss://dourada.example/watch-connect',
            'seatIndex': 0,
            'phase': 'playing',
            'spectator': true,
            'spectatorCount': 3,
            'seats': List<Object?>.filled(6, null),
          }),
          200,
        );
      }),
    );

    final entry = await service.watchTable(4);

    expect(sentRequest.method, 'POST');
    expect(sentRequest.url.path, '/api/tables/4/watch');
    expect(entry.spectator, isTrue);
    expect(entry.spectatorCount, 3);
    expect(entry.phase, LobbyTablePhase.playing);
    expect(await service.savedSession(), isNull);
    service.dispose();
  });

  test('usa nome e foto do perfil na mesa local', () async {
''')

path = 'test/widget_test.dart'
replace_once(path,
'''    expect(find.text('DOURADA'), findsOneWidget);
    expect(find.text('LOBBY DOURADINHA'), findsNothing);
''',
'''    expect(find.text('DOURADA'), findsOneWidget);
    expect(find.text('LOBBY DOURADINHA'), findsNothing);
    expect(find.text('VER'), findsOneWidget);
''')

print('Modo espectador aplicado com sucesso.')
