import 'dart:async';
import 'dart:convert';

import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TableSession extends ChangeNotifier {
  TableSession({
    this.entry,
    http.Client? client,
    String? serverUrl,
  })  : _client = client ?? http.Client(),
        _serverUrl = normalizeServerUrl(
          entry?.serverUrl ??
              serverUrl ??
              const String.fromEnvironment('DOURADA_SERVER_URL'),
        ) {
    if (entry != null) {
      tableNumber = entry!.tableNumber;
      playerToken = entry!.playerToken;
      websocketUrl = entry!.websocketUrl;
      seatIndex = entry!.seatIndex;
      phase = entry!.phase;
      seats = entry!.seats;
      fillBotsVotingVersion = entry!.fillBotsVotingVersion;
      challengeVotingVersion = entry!.challengeVotingVersion;
      waitingStartAt = entry!.waitingStartAt;
      fillBotsVote = entry!.fillBotsVote;
      challengeVote = entry!.challengeVote;
      spectatorCount = entry!.spectatorCount;
      spectatorHandCounts = entry!.spectatorHandCounts;
    }
  }

  static const tableNumberKey = LobbyService.tableNumberKey;
  static const playerTokenKey = LobbyService.playerTokenKey;

  final TableEntry? entry;
  final http.Client _client;
  final String _serverUrl;
  DouradinhaGame? _game;
  SharedPreferences? _preferences;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _presencePaused = false;
  bool _applyingRemoteState = false;

  String? tableNumber;
  String? playerToken;
  String? websocketUrl;
  int seatIndex = 0;
  LobbyTablePhase phase = LobbyTablePhase.playing;
  List<LobbySeat?> seats = List<LobbySeat?>.filled(6, null);
  int fillBotsVotingVersion = 0;
  int challengeVotingVersion = 0;
  DateTime? waitingStartAt;
  FillBotsVote? fillBotsVote;
  TeamChallengeVote? challengeVote;
  String? errorMessage;
  bool connecting = false;
  bool requestingFillBotsVote = false;
  bool submittingFillBotsVote = false;
  bool submittingChallengeVote = false;
  bool connected = false;
  bool replacementBotActive = false;
  bool seatUnavailable = false;
  bool spectatorMatchEnded = false;
  int spectatorCount = 0;
  List<int> spectatorHandCounts = const [];
  String? _reportedShownFillBotsVoteId;

  bool get enabled => _serverUrl.isNotEmpty && entry?.online != false;
  bool get isSpectator => entry?.spectator == true;
  bool get applyingRemoteState => _applyingRemoteState;
  bool get serverControlsAutomation => enabled;
  bool get waiting =>
      !isSpectator && enabled && phase == LobbyTablePhase.waiting;
  bool get canPlayHere => isSpectator
      ? (!enabled ||
          (connected &&
              phase == LobbyTablePhase.playing &&
              !spectatorMatchEnded))
      : (!enabled || (connected && phase == LobbyTablePhase.playing));
  int get playerCount => seats.where((seat) => seat != null).length;
  int get missingPlayers => 6 - playerCount;
  int spectatorHandCountFor(int playerIndex) =>
      playerIndex >= 0 && playerIndex < spectatorHandCounts.length
          ? spectatorHandCounts[playerIndex]
          : 0;
  bool get isFillBotsVoteRequester =>
      fillBotsVote?.requesterSeatIndex == seatIndex;
  bool get canRespondToFillBotsVote {
    final vote = fillBotsVote;
    return !isSpectator &&
        vote != null &&
        vote.expiresAt != null &&
        vote.requesterSeatIndex != seatIndex &&
        vote.participantSeatIndexes.contains(seatIndex) &&
        vote.shownAtFor(seatIndex) != null &&
        vote.voteFor(seatIndex) == null;
  }

  bool get canRespondToChallengeVote {
    final vote = challengeVote;
    return !isSpectator &&
        enabled &&
        challengeVotingVersion >= 1 &&
        vote != null &&
        DateTime.now().isBefore(vote.expiresAt) &&
        vote.participantSeatIndexes.contains(seatIndex) &&
        vote.voteFor(seatIndex) == null &&
        !submittingChallengeVote &&
        _channel != null;
  }

  ChallengeVoteChoice? get localChallengeVote =>
      challengeVote?.voteFor(seatIndex);

  String get connectionLabel {
    if (isSpectator) {
      if (connecting) return 'Conectando para assistir...';
      if (connected) return 'Assistindo mesa $tableNumber';
      return 'Transmissão da mesa $tableNumber';
    }
    if (!enabled) return 'Mesa local';
    if (connecting) return 'Conectando...';
    if (waiting) return 'Mesa $tableNumber • aguardando';
    if (connected) return 'Mesa $tableNumber';
    if (replacementBotActive) return 'Mesa $tableNumber • robô assumiu';
    return 'Mesa $tableNumber • offline';
  }

  Future<void> initialize(
    DouradinhaGame game,
    SharedPreferences preferences,
  ) async {
    _game = game;
    _preferences = preferences;
    _configureSeats();
    if (!enabled || _disposed) return;
    _applyEntry(entry!);
    await _connectSocket();
  }

  Future<void> fillRemainingWithBots() async {
    if (!enabled || !waiting || playerToken == null || tableNumber == null) {
      return;
    }
    if (fillBotsVotingVersion < 2) {
      errorMessage =
          'O servidor da mesa precisa ser atualizado antes de iniciar a votação.';
      notifyListeners();
      return;
    }
    connecting = true;
    requestingFillBotsVote = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/tables/$tableNumber/fill-bots'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'playerToken': playerToken,
              'humanSeatIndexes': [
                for (var index = 0; index < seats.length; index++)
                  if (seats[index] != null && !seats[index]!.isBot) index,
              ],
            }),
          )
          .timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw StateError(
            payload['error'] as String? ?? 'Não foi possível iniciar.');
      }
      _applyRoomPayload(payload);
    } on Object catch (error) {
      errorMessage = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      connecting = false;
      requestingFillBotsVote = false;
      if (!_disposed) notifyListeners();
    }
  }

  void respondToFillBotsVote(bool accepted) {
    if (!canRespondToFillBotsVote ||
        submittingFillBotsVote ||
        _channel == null) {
      return;
    }
    submittingFillBotsVote = true;
    _channel!.sink.add(jsonEncode({
      'type': 'fillBotsVote',
      'voteId': fillBotsVote!.id,
      'accepted': accepted,
    }));
    notifyListeners();
  }

  void reportFillBotsVoteShown(String voteId) {
    final vote = fillBotsVote;
    if (vote == null ||
        vote.id != voteId ||
        vote.requesterSeatIndex == seatIndex ||
        !vote.participantSeatIndexes.contains(seatIndex) ||
        vote.shownAtFor(seatIndex) != null ||
        _channel == null ||
        _reportedShownFillBotsVoteId == voteId) {
      return;
    }
    _reportedShownFillBotsVoteId = voteId;
    _channel!.sink.add(jsonEncode({
      'type': 'fillBotsVoteShown',
      'voteId': voteId,
    }));
  }

  void respondToChallengeVote(ChallengeVoteChoice choice) {
    final vote = challengeVote;
    if (!canRespondToChallengeVote || vote == null) return;
    submittingChallengeVote = true;
    _channel!.sink.add(jsonEncode({
      'type': 'challengeVote',
      'voteId': vote.id,
      'choice': choice.wireValue,
    }));
    notifyListeners();
  }

  Future<void> startNewMatch(DouradinhaGame game) async {
    if (!enabled) {
      final preferences = _preferences;
      if (preferences != null) {
        await preferences.remove(tableNumberKey);
        await preferences.remove(playerTokenKey);
      }
      game.restart();
      return;
    }
    _channel?.sink.add(jsonEncode({'type': 'restart'}));
  }

  Future<void> leaveTable() async {
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
    final currentTable = tableNumber;
    final currentToken = playerToken;
    if (enabled && currentTable != null && currentToken != null) {
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/tables/$currentTable/leave'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerToken': currentToken}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        throw StateError(
          payload['error'] as String? ?? 'Não foi possível sair da mesa.',
        );
      }
    }

    _presencePaused = true;
    _reconnectTimer?.cancel();
    connected = false;
    replacementBotActive = false;
    playerToken = null;
    websocketUrl = null;
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(tableNumberKey),
      preferences.remove(playerTokenKey),
      preferences.remove(LobbyService.seatIndexKey),
    ]);
    unawaited(_closeChannel());
    if (!_disposed) notifyListeners();
  }

  Future<void> pausePresence() async {
    if (!enabled || _disposed || _presencePaused) return;
    _presencePaused = true;
    _reconnectTimer?.cancel();
    connected = false;
    notifyListeners();
    await _closeChannel();
  }

  Future<void> resumePresence() async {
    if (!enabled || _disposed || !_presencePaused) return;
    _presencePaused = false;
    await _rejoinAndConnect();
  }

  void syncGame(DouradinhaGame game) {
    if (isSpectator ||
        _applyingRemoteState ||
        !canPlayHere ||
        _channel == null) {
      return;
    }
    _channel!.sink
        .add(jsonEncode({'type': 'state', 'gameState': game.toJson()}));
  }

  void _applyEntry(TableEntry value) {
    tableNumber = value.tableNumber;
    playerToken = value.playerToken;
    websocketUrl = value.websocketUrl;
    seatIndex = value.seatIndex;
    phase = value.phase;
    seats = value.seats;
    fillBotsVotingVersion = value.fillBotsVotingVersion;
    challengeVotingVersion = value.challengeVotingVersion;
    waitingStartAt = value.waitingStartAt;
    fillBotsVote = value.fillBotsVote;
    challengeVote = value.challengeVote;
    spectatorCount = value.spectatorCount;
    spectatorHandCounts = value.spectatorHandCounts;
    _configureSeats();
    _restoreRemoteState(value.gameState);
  }

  void _applyRoomPayload(Map<String, dynamic> payload) {
    phase = LobbyTablePhase.values.byName(payload['phase'] as String);
    final votingVersion = payload['fillBotsVotingVersion'];
    fillBotsVotingVersion = votingVersion is num ? votingVersion.toInt() : 0;
    final challengeVersion = payload['challengeVotingVersion'];
    challengeVotingVersion =
        challengeVersion is num ? challengeVersion.toInt() : 0;
    seatIndex = payload['seatIndex'] as int? ?? seatIndex;
    seats = (payload['seats'] as List<Object?>)
        .map((value) => value == null
            ? null
            : LobbySeat.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList(growable: false);
    final countdownValue = payload['waitingStartAt'];
    waitingStartAt = countdownValue is num
        ? DateTime.fromMillisecondsSinceEpoch(countdownValue.toInt())
        : null;
    fillBotsVote = FillBotsVote.fromJsonValue(payload['fillBotsVote']);
    challengeVote = TeamChallengeVote.fromJsonValue(payload['challengeVote']);
    spectatorCount = (payload['spectatorCount'] as num?)?.toInt() ?? 0;
    final rawSpectatorHandCounts = payload['spectatorHandCounts'];
    spectatorHandCounts = rawSpectatorHandCounts is List
        ? rawSpectatorHandCounts
            .map((value) => value is num ? value.toInt() : 0)
            .toList(growable: false)
        : const [];
    final gameState = payload['gameState'];
    if (isSpectator &&
        (phase != LobbyTablePhase.playing ||
            (gameState is Map && gameState['phase'] == 'gameOver'))) {
      spectatorMatchEnded = true;
      _presencePaused = true;
      _reconnectTimer?.cancel();
    }
    if (fillBotsVote?.id != _reportedShownFillBotsVoteId) {
      _reportedShownFillBotsVoteId = null;
    }
    submittingFillBotsVote = false;
    submittingChallengeVote = false;
    _configureSeats();
    _restoreRemoteState(gameState);
  }

  void _configureSeats() {
    _game?.configureSeats([
      for (final seat in seats)
        seat == null
            ? null
            : (
                name: seat.name,
                isHuman: !seat.isBot,
                photoUrl: seat.photoUrl,
              ),
    ]);
  }

  Future<void> _connectSocket() async {
    if (_disposed || _presencePaused || connecting || websocketUrl == null) {
      return;
    }
    connecting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _closeChannel();
      final channel = WebSocketChannel.connect(Uri.parse(websocketUrl!));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));
      if (_disposed || channel != _channel) return;
      connected = true;
      replacementBotActive = false;
      _reportedShownFillBotsVoteId = null;
      _subscription = channel.stream.listen(
        _handleSocketMessage,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
        cancelOnError: true,
      );
    } on Object {
      connected = false;
      replacementBotActive =
          !isSpectator && phase == LobbyTablePhase.playing;
      errorMessage = isSpectator
          ? 'Não foi possível conectar à transmissão.'
          : 'Não foi possível conectar à mesa.';
      _scheduleReconnect();
    } finally {
      connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _handleSocketMessage(dynamic rawMessage) {
    if (rawMessage is! String || rawMessage == 'pong') return;
    try {
      final message = jsonDecode(rawMessage) as Map<String, dynamic>;
      if (message['type'] == 'room') {
        _applyRoomPayload(message);
        notifyListeners();
      }
    } on Object {
      errorMessage = 'A mesa enviou uma atualização inválida.';
      notifyListeners();
    }
  }

  void _restoreRemoteState(Object? value) {
    if (value is! Map || _game == null) return;
    _applyingRemoteState = true;
    try {
      final restored = _game!.restoreState(Map<String, dynamic>.from(value));
      if (restored) _normalizeLegacyTeamMessages();
    } finally {
      _applyingRemoteState = false;
    }
  }

  void _normalizeLegacyTeamMessages() {
    final game = _game;
    if (game == null) return;

    String normalize(String message) {
      var normalized = message
          .replaceAll(
            RegExp(r'(?:o )?trio azul', caseSensitive: false),
            game.teamLabel(0),
          )
          .replaceAll(
            RegExp(r'(?:o )?trio dourado', caseSensitive: false),
            game.teamLabel(1),
          );
      const conjugations = <String, String>{
        'Nós jogou': 'Nós jogamos',
        'Eles jogou': 'Eles jogaram',
        'Nós descartou': 'Nós descartamos',
        'Eles descartou': 'Eles descartaram',
        'Nós venceu': 'Nós vencemos',
        'Eles venceu': 'Eles venceram',
        'Nós ganhou': 'Nós ganhamos',
        'Eles ganhou': 'Eles ganharam',
        'Nós marcou': 'Nós marcamos',
        'Eles marcou': 'Eles marcaram',
        'Nós decidiu': 'Nós decidimos',
        'Eles decidiu': 'Eles decidiram',
        'Nós aceitou': 'Nós aceitamos',
        'Eles aceitou': 'Eles aceitaram',
        'Nós correu': 'Nós corremos',
        'Eles correu': 'Eles correram',
        'Nós pediu': 'Nós pedimos',
        'Eles pediu': 'Eles pediram',
      };
      for (final entry in conjugations.entries) {
        normalized = normalized.replaceAll(entry.key, entry.value);
      }
      return normalized;
    }

    game.statusMessage = normalize(game.statusMessage);
    for (var index = 0; index < game.history.length; index++) {
      game.history[index] = normalize(game.history[index]);
    }
    final notice = game.challengeNotice;
    if (notice != null) game.challengeNotice = normalize(notice);
  }

  Future<void> _rejoinAndConnect() async {
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

  Future<void> clearUnavailableSeat() async {
    if (_disposed) return;
    _presencePaused = true;
    _reconnectTimer?.cancel();
    connected = false;
    replacementBotActive = false;
    seatUnavailable = false;
    errorMessage = null;
    playerToken = null;
    websocketUrl = null;
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(tableNumberKey),
      preferences.remove(playerTokenKey),
      preferences.remove(LobbyService.seatIndexKey),
    ]);
    unawaited(_closeChannel());
    if (!_disposed) notifyListeners();
  }

  void _handleSocketClosed() {
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

  void _scheduleReconnect() {
    if (_disposed || _presencePaused || _reconnectTimer?.isActive == true) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 3), _rejoinAndConnect);
  }

  Future<void> _closeChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.sink.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_closeChannel());
    _client.close();
    super.dispose();
  }
}
