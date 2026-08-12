import 'dart:async';
import 'dart:convert';

import 'package:dourada/game/douradinha_game.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TableSession extends ChangeNotifier {
  TableSession({
    http.Client? client,
    String? serverUrl,
  })  : _client = client ?? http.Client(),
        _serverUrl = (serverUrl ??
                const String.fromEnvironment(
                  'DOURADA_SERVER_URL',
                ))
            .replaceFirst(RegExp(r'/$'), '');

  static const tableNumberKey = 'douradinha_numero_mesa_v1';
  static const playerTokenKey = 'douradinha_token_jogador_v1';

  final http.Client _client;
  final String _serverUrl;
  SharedPreferences? _preferences;
  DouradinhaGame? _game;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _presencePaused = false;
  bool _applyingRemoteState = false;
  bool _startingNewMatch = false;
  bool _ignoreNextSocketState = false;

  String? tableNumber;
  String? playerToken;
  String? websocketUrl;
  String? errorMessage;
  bool connecting = false;
  bool connected = false;
  bool replacementBotActive = false;

  bool get enabled => _serverUrl.isNotEmpty;
  bool get applyingRemoteState => _applyingRemoteState;
  bool get canPlayHere => !enabled || tableNumber == null || connected;

  String get connectionLabel {
    if (!enabled) return 'Mesa local';
    if (connecting) return 'Conectando...';
    if (connected) return 'Mesa $tableNumber';
    if (replacementBotActive) return 'Mesa $tableNumber • robô assumiu';
    return tableNumber == null
        ? 'Criando mesa...'
        : 'Mesa $tableNumber • offline';
  }

  Future<void> initialize(
    DouradinhaGame game,
    SharedPreferences preferences,
  ) async {
    _game = game;
    _preferences = preferences;
    if (!enabled || _disposed) return;

    tableNumber = preferences.getString(tableNumberKey);
    playerToken = preferences.getString(playerTokenKey);
    if (game.phase == MatchPhase.gameOver) game.restart();
    await _openSession(isReconnect: false);
  }

  Future<void> startNewMatch(DouradinhaGame game) async {
    if (_startingNewMatch) return;
    _startingNewMatch = true;
    _reconnectTimer?.cancel();
    connected = false;
    replacementBotActive = false;
    await _closeChannel();
    await _clearCredentials();
    game.restart();
    _startingNewMatch = false;
    if (enabled && !_disposed) await _openSession(isReconnect: false);
  }

  Future<void> pausePresence() async {
    if (!enabled || _disposed || _presencePaused) return;
    _presencePaused = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    connected = false;
    if (!_disposed) notifyListeners();
    await _closeChannel();
  }

  Future<void> resumePresence() async {
    if (!enabled || _disposed || !_presencePaused) return;
    _presencePaused = false;
    await _openSession(isReconnect: true);
  }

  void syncGame(DouradinhaGame game) {
    if (_applyingRemoteState || !connected || _channel == null) return;
    _channel!.sink.add(
      jsonEncode({
        'type': 'state',
        'gameState': game.toJson(),
      }),
    );
  }

  Future<void> _openSession({required bool isReconnect}) async {
    if (_disposed || _presencePaused || connecting || _startingNewMatch) return;
    connecting = true;
    errorMessage = null;
    notifyListeners();

    final previousTable = tableNumber;
    final previousToken = playerToken;
    try {
      if (_game!.phase == MatchPhase.gameOver && isReconnect) {
        _game!.restart();
      }
      final response = await _client
          .post(
            Uri.parse('$_serverUrl/api/session'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (previousTable != null) 'tableNumber': previousTable,
              if (previousToken != null) 'playerToken': previousToken,
              'gameState': _game!.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw StateError('Servidor respondeu ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      tableNumber = payload['tableNumber'] as String;
      playerToken = payload['playerToken'] as String;
      websocketUrl = payload['websocketUrl'] as String;
      await _saveCredentials();

      final createdAfterEndedTable = response.statusCode == 201 &&
          previousTable != null &&
          payload['previousSessionEnded'] == true;
      if (createdAfterEndedTable) {
        // A mesa anterior terminou enquanto o usuário estava fora. A nova mesa
        // começa zerada, como uma nova partida de verdade.
        _game!.restart();
        _ignoreNextSocketState = true;
      } else {
        _restoreRemoteState(payload['gameState']);
      }
      await _connectSocket();
      if (createdAfterEndedTable) syncGame(_game!);
    } on Object {
      connected = false;
      replacementBotActive = previousTable != null;
      errorMessage = 'Não foi possível conectar à mesa. O jogo local continua.';
      if (isReconnect) _scheduleReconnect();
    } finally {
      connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _connectSocket() async {
    await _closeChannel();
    final channel = WebSocketChannel.connect(Uri.parse(websocketUrl!));
    _channel = channel;
    await channel.ready.timeout(const Duration(seconds: 12));
    if (_disposed || channel != _channel) {
      await channel.sink.close();
      return;
    }
    connected = true;
    replacementBotActive = false;
    _subscription = channel.stream.listen(
      _handleSocketMessage,
      onDone: _handleSocketClosed,
      onError: (_) => _handleSocketClosed(),
      cancelOnError: true,
    );
    _startHeartbeat();
  }

  void _handleSocketMessage(dynamic rawMessage) {
    if (rawMessage is! String) return;
    if (rawMessage == 'pong') return;
    final message = jsonDecode(rawMessage) as Map<String, dynamic>;
    if (message['type'] == 'state') {
      if (_ignoreNextSocketState) {
        _ignoreNextSocketState = false;
        return;
      }
      _restoreRemoteState(message['gameState']);
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

  void _handleSocketClosed() {
    _heartbeatTimer?.cancel();
    if (_disposed || _startingNewMatch) return;
    connected = false;
    replacementBotActive = tableNumber != null;
    notifyListeners();
    if (!_presencePaused) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed ||
        _presencePaused ||
        _startingNewMatch ||
        _reconnectTimer?.isActive == true) {
      return;
    }
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => _openSession(isReconnect: true),
    );
  }

  Future<void> _saveCredentials() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString(tableNumberKey, tableNumber!);
    await preferences.setString(playerTokenKey, playerToken!);
  }

  Future<void> _clearCredentials() async {
    tableNumber = null;
    playerToken = null;
    websocketUrl = null;
    final preferences = _preferences;
    if (preferences != null) {
      await preferences.remove(tableNumberKey);
      await preferences.remove(playerTokenKey);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _closeChannel() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.sink.close();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    if (!connected || _presencePaused || _channel == null) return;
    _channel!.sink.add('ping');
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
