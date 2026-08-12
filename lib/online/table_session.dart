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
        _serverUrl = (entry?.serverUrl ??
                serverUrl ??
                const String.fromEnvironment('DOURADA_SERVER_URL'))
            .replaceFirst(RegExp(r'/$'), '') {
    if (entry != null) {
      tableNumber = entry!.tableNumber;
      playerToken = entry!.playerToken;
      websocketUrl = entry!.websocketUrl;
      seatIndex = entry!.seatIndex;
      phase = entry!.phase;
      seats = entry!.seats;
      waitingStartAt = entry!.waitingStartAt;
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
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _presencePaused = false;
  bool _applyingRemoteState = false;

  String? tableNumber;
  String? playerToken;
  String? websocketUrl;
  int seatIndex = 0;
  LobbyTablePhase phase = LobbyTablePhase.playing;
  List<LobbySeat?> seats = List<LobbySeat?>.filled(6, null);
  DateTime? waitingStartAt;
  String? errorMessage;
  bool connecting = false;
  bool connected = false;
  bool replacementBotActive = false;

  bool get enabled => _serverUrl.isNotEmpty && entry?.online != false;
  bool get applyingRemoteState => _applyingRemoteState;
  bool get serverControlsAutomation => enabled;
  bool get waiting => enabled && phase == LobbyTablePhase.waiting;
  bool get canPlayHere =>
      !enabled || (connected && phase == LobbyTablePhase.playing);
  int get playerCount => seats.where((seat) => seat != null).length;
  int get missingPlayers => 6 - playerCount;

  String get connectionLabel {
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
    if (!enabled || _disposed) return;
    _applyEntry(entry!);
    await _connectSocket();
  }

  Future<void> fillRemainingWithBots() async {
    if (!enabled || !waiting || playerToken == null || tableNumber == null) {
      return;
    }
    connecting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/tables/$tableNumber/fill-bots'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerToken': playerToken}),
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
      if (!_disposed) notifyListeners();
    }
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

  Future<void> pausePresence() async {
    if (!enabled || _disposed || _presencePaused) return;
    _presencePaused = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
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
    if (_applyingRemoteState || !canPlayHere || _channel == null) {
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
    waitingStartAt = value.waitingStartAt;
    _configureSeats();
    _restoreRemoteState(value.gameState);
  }

  void _applyRoomPayload(Map<String, dynamic> payload) {
    phase = LobbyTablePhase.values.byName(payload['phase'] as String);
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
    _configureSeats();
    _restoreRemoteState(payload['gameState']);
  }

  void _configureSeats() {
    _game?.configureSeats([
      for (final seat in seats)
        seat == null ? null : (name: seat.name, isHuman: !seat.isBot),
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
      _subscription = channel.stream.listen(
        _handleSocketMessage,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
        cancelOnError: true,
      );
      _startHeartbeat();
    } on Object {
      connected = false;
      replacementBotActive = phase == LobbyTablePhase.playing;
      errorMessage = 'Não foi possível conectar à mesa.';
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
      _game!.restoreState(Map<String, dynamic>.from(value));
    } finally {
      _applyingRemoteState = false;
    }
  }

  Future<void> _rejoinAndConnect() async {
    if (playerToken == null || tableNumber == null) return;
    try {
      final response = await _client.post(
        Uri.parse('$_serverUrl/api/tables/$tableNumber/join'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'playerToken': playerToken}),
      );
      if (response.statusCode != 200) throw StateError('Sessão encerrada.');
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      websocketUrl = payload['websocketUrl'] as String;
      _applyRoomPayload(payload);
      await _connectSocket();
    } on Object {
      errorMessage = 'Sua cadeira não está mais disponível.';
      notifyListeners();
    }
  }

  void _handleSocketClosed() {
    _heartbeatTimer?.cancel();
    if (_disposed) return;
    connected = false;
    replacementBotActive = phase == LobbyTablePhase.playing;
    notifyListeners();
    if (!_presencePaused) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _presencePaused || _reconnectTimer?.isActive == true) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 3), _rejoinAndConnect);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _sendHeartbeat());
  }

  void _sendHeartbeat() {
    if (connected && !_presencePaused) _channel?.sink.add('ping');
  }

  Future<void> _closeChannel() async {
    _heartbeatTimer?.cancel();
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
    _heartbeatTimer?.cancel();
    unawaited(_closeChannel());
    _client.close();
    super.dispose();
  }
}
