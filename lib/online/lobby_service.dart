import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LobbyTablePhase { empty, waiting, playing }

const botAvatarAssetCount = 10;

String botAvatarAsset(int number) =>
    'assets/images/avatar/robos/robo_${number.toString().padLeft(2, '0')}.png';

class SavedTableSession {
  const SavedTableSession(
      {required this.tableNumber, required this.playerToken});

  final String tableNumber;
  final String playerToken;
}

class LobbySeat {
  const LobbySeat({
    required this.index,
    required this.kind,
    required this.name,
    required this.team,
    required this.connected,
    this.photoUrl,
  });

  final int index;
  final String kind;
  final String name;
  final int team;
  final bool connected;
  final String? photoUrl;

  bool get isBot => kind == 'bot';

  factory LobbySeat.fromJson(Map<String, dynamic> json) => LobbySeat(
        index: json['index'] as int,
        kind: json['kind'] as String,
        name: json['name'] as String,
        team: json['team'] as int,
        connected: json['connected'] as bool? ?? true,
        photoUrl: json['photoUrl'] as String?,
      );
}

class LobbyTable {
  const LobbyTable({
    required this.tableNumber,
    required this.phase,
    required this.playerCount,
    required this.humanCount,
    required this.botCount,
    required this.capacity,
    required this.seats,
  });

  final int tableNumber;
  final LobbyTablePhase phase;
  final int playerCount;
  final int humanCount;
  final int botCount;
  final int capacity;
  final List<LobbySeat?> seats;

  bool get canJoin =>
      phase != LobbyTablePhase.playing && playerCount < capacity;
  bool get canWatch => phase == LobbyTablePhase.playing;

  factory LobbyTable.fromJson(Map<String, dynamic> json) => LobbyTable(
        tableNumber: json['tableNumber'] as int,
        phase: LobbyTablePhase.values.byName(json['status'] as String),
        playerCount: json['playerCount'] as int,
        humanCount: json['humanCount'] as int,
        botCount: json['botCount'] as int,
        capacity: json['capacity'] as int,
        seats: (json['seats'] as List<Object?>)
            .map(
              (seat) => seat == null
                  ? null
                  : LobbySeat.fromJson(Map<String, dynamic>.from(seat as Map)),
            )
            .toList(growable: false),
      );
}

LobbyTable? selectQuickJoinTable(Iterable<LobbyTable> tables) {
  final ordered = tables.where((table) => table.canJoin).toList()
    ..sort((left, right) => left.tableNumber.compareTo(right.tableNumber));
  for (final phase in [LobbyTablePhase.waiting, LobbyTablePhase.empty]) {
    for (final table in ordered) {
      if (table.phase == phase) return table;
    }
  }
  return null;
}

class TableEntry {
  const TableEntry({
    required this.serverUrl,
    required this.tableNumber,
    required this.playerToken,
    required this.websocketUrl,
    required this.seatIndex,
    required this.phase,
    required this.seats,
    this.fillBotsVotingVersion = 0,
    this.challengeVotingVersion = 0,
    this.waitingStartAt,
    this.fillBotsVote,
    this.challengeVote,
    this.gameState,
    this.spectator = false,
    this.spectatorCount = 0,
    this.spectatorHandCounts = const [],
  });

  final String serverUrl;
  final String tableNumber;
  final String playerToken;
  final String websocketUrl;
  final int seatIndex;
  final LobbyTablePhase phase;
  final List<LobbySeat?> seats;
  final int fillBotsVotingVersion;
  final int challengeVotingVersion;
  final DateTime? waitingStartAt;
  final FillBotsVote? fillBotsVote;
  final TeamChallengeVote? challengeVote;
  final Object? gameState;
  final bool spectator;
  final int spectatorCount;
  final List<int> spectatorHandCounts;

  bool get online => serverUrl.isNotEmpty;

  factory TableEntry.fromJson(String serverUrl, Map<String, dynamic> json) =>
      TableEntry(
        serverUrl: serverUrl,
        tableNumber: json['tableNumber'] as String,
        playerToken: json['playerToken'] as String,
        websocketUrl: json['websocketUrl'] as String,
        seatIndex: json['seatIndex'] as int,
        phase: LobbyTablePhase.values.byName(json['phase'] as String),
        seats: (json['seats'] as List<Object?>)
            .map(
              (seat) => seat == null
                  ? null
                  : LobbySeat.fromJson(Map<String, dynamic>.from(seat as Map)),
            )
            .toList(growable: false),
        fillBotsVotingVersion:
            (json['fillBotsVotingVersion'] as num?)?.toInt() ?? 0,
        challengeVotingVersion:
            (json['challengeVotingVersion'] as num?)?.toInt() ?? 0,
        waitingStartAt: _dateTimeFromMilliseconds(json['waitingStartAt']),
        fillBotsVote: FillBotsVote.fromJsonValue(json['fillBotsVote']),
        challengeVote: TeamChallengeVote.fromJsonValue(json['challengeVote']),
        gameState: json['gameState'],
        spectator: json['spectator'] as bool? ?? false,
        spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
        spectatorHandCounts:
            (json['spectatorHandCounts'] as List<Object?>? ??
                    const <Object?>[])
                .map((value) => value is num ? value.toInt() : 0)
                .toList(growable: false),
      );
}

class FillBotsVote {
  const FillBotsVote({
    required this.id,
    required this.requesterSeatIndex,
    required this.participantSeatIndexes,
    required this.votes,
    required this.shownAt,
    required this.expiresAt,
  });

  final String id;
  final int requesterSeatIndex;
  final List<int> participantSeatIndexes;
  final List<bool?> votes;
  final List<DateTime?> shownAt;
  final DateTime? expiresAt;

  bool? voteFor(int seatIndex) =>
      seatIndex >= 0 && seatIndex < votes.length ? votes[seatIndex] : null;
  DateTime? shownAtFor(int seatIndex) =>
      seatIndex >= 0 && seatIndex < shownAt.length ? shownAt[seatIndex] : null;

  static FillBotsVote? fromJsonValue(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final id = json['id'];
    final requester = json['requesterSeatIndex'];
    final participants = json['participantSeatIndexes'];
    final rawVotes = json['votes'];
    final rawShownAt = json['shownAt'];
    final expires = json['expiresAt'];
    if (id is! String ||
        requester is! num ||
        participants is! List ||
        rawVotes is! List ||
        rawShownAt is! List ||
        (expires != null && expires is! num)) {
      return null;
    }
    final participantIndexes =
        participants.whereType<num>().map((index) => index.toInt()).toList();
    if (participantIndexes.length != participants.length) return null;
    return FillBotsVote(
      id: id,
      requesterSeatIndex: requester.toInt(),
      participantSeatIndexes: participantIndexes,
      votes: rawVotes
          .map<bool?>((vote) => vote is bool ? vote : null)
          .toList(growable: false),
      shownAt: rawShownAt
          .map<DateTime?>((value) => value is num
              ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
              : null)
          .toList(growable: false),
      expiresAt: expires is num
          ? DateTime.fromMillisecondsSinceEpoch(expires.toInt())
          : null,
    );
  }
}

enum ChallengeVoteChoice {
  accept('accept'),
  fold('fold'),
  raise('raise');

  const ChallengeVoteChoice(this.wireValue);

  final String wireValue;

  static ChallengeVoteChoice? fromWireValue(Object? value) {
    for (final choice in values) {
      if (choice.wireValue == value) return choice;
    }
    return null;
  }
}

class TeamChallengeVote {
  static const responseTimeout = Duration(seconds: 15);

  const TeamChallengeVote({
    required this.id,
    required this.targetTeam,
    required this.requestedValue,
    required this.challengerPlayer,
    required this.expiresAt,
    required this.participantSeatIndexes,
    required this.votes,
  });

  final String id;
  final int targetTeam;
  final int requestedValue;
  final int challengerPlayer;
  final DateTime expiresAt;
  final List<int> participantSeatIndexes;
  final List<ChallengeVoteChoice?> votes;

  ChallengeVoteChoice? voteFor(int seatIndex) =>
      seatIndex >= 0 && seatIndex < votes.length ? votes[seatIndex] : null;

  static TeamChallengeVote? fromJsonValue(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final id = json['id'];
    final targetTeam = json['targetTeam'];
    final requestedValue = json['requestedValue'];
    final challengerPlayer = json['challengerPlayer'];
    final expiresAt = _dateTimeFromMilliseconds(json['expiresAt']);
    final participants = json['participantSeatIndexes'];
    final rawVotes = json['votes'];
    if (id is! String ||
        targetTeam is! num ||
        requestedValue is! num ||
        challengerPlayer is! num ||
        expiresAt == null ||
        participants is! List ||
        rawVotes is! List) {
      return null;
    }
    final participantIndexes =
        participants.whereType<num>().map((index) => index.toInt()).toList();
    if (participantIndexes.length != participants.length) return null;
    return TeamChallengeVote(
      id: id,
      targetTeam: targetTeam.toInt(),
      requestedValue: requestedValue.toInt(),
      challengerPlayer: challengerPlayer.toInt(),
      expiresAt: expiresAt,
      participantSeatIndexes: participantIndexes,
      votes: rawVotes
          .map<ChallengeVoteChoice?>(ChallengeVoteChoice.fromWireValue)
          .toList(growable: false),
    );
  }
}

DateTime? _dateTimeFromMilliseconds(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

String normalizeServerUrl(String value) =>
    value.replaceAll('\uFEFF', '').trim().replaceFirst(RegExp(r'/+$'), '');

class LobbyService {
  LobbyService({http.Client? client, String? serverUrl})
      : _client = client ?? http.Client(),
        serverUrl = normalizeServerUrl(
          serverUrl ?? const String.fromEnvironment('DOURADA_SERVER_URL'),
        );

  static const tableNumberKey = 'douradinha_numero_mesa_v2';
  static const playerTokenKey = 'douradinha_token_jogador_v2';
  static const seatIndexKey = 'douradinha_cadeira_jogador_v2';
  static const _pendingDeclineTableKey = 'douradinha_recusa_mesa_v1';
  static const _pendingDeclineTokenKey = 'douradinha_recusa_token_v1';

  final http.Client _client;
  final String serverUrl;
  WebSocketChannel? _lobbyChannel;

  bool get enabled => serverUrl.isNotEmpty;

  Future<List<LobbyTable>> fetchTables() async {
    if (!enabled) return _localTables();
    final response = await _client
        .get(Uri.parse('$serverUrl/api/lobby'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Servidor respondeu ${response.statusCode}.');
    }
    return decodeTables(response.body);
  }

  Stream<List<LobbyTable>> watchTables() async* {
    if (!enabled) {
      yield _localTables();
      return;
    }
    final serverUri = Uri.parse(serverUrl);
    final websocketUri = serverUri.replace(
      scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
      path: '${serverUri.path}/api/lobby/connect',
    );
    final channel = WebSocketChannel.connect(websocketUri);
    _lobbyChannel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 12));
      await for (final rawMessage in channel.stream) {
        if (rawMessage is! String) continue;
        yield decodeTables(rawMessage);
      }
    } finally {
      if (identical(_lobbyChannel, channel)) _lobbyChannel = null;
      unawaited(channel.sink.close());
    }
  }

  static List<LobbyTable> decodeTables(String rawMessage) {
    final payload = jsonDecode(rawMessage) as Map<String, dynamic>;
    if (payload['tables'] is! List<Object?>) {
      throw const FormatException('Atualização do lobby inválida.');
    }
    return (payload['tables'] as List<Object?>)
        .map((value) =>
            LobbyTable.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList(growable: false);
  }

  Future<TableEntry> joinTable(
    int tableNumber, {
    String? firebaseIdToken,
    String? playerName,
    String? playerPhotoUrl,
  }) async {
    if (!enabled) {
      final botAvatars = List<int>.generate(
        botAvatarAssetCount,
        (index) => index + 1,
      )..shuffle(Random());
      return TableEntry(
        serverUrl: '',
        tableNumber: '$tableNumber',
        playerToken: 'local',
        websocketUrl: '',
        seatIndex: 0,
        phase: LobbyTablePhase.playing,
        seats: List<LobbySeat?>.generate(
          6,
          (index) => LobbySeat(
            index: index,
            kind: index == 0 ? 'human' : 'bot',
            name: index == 0 ? (playerName ?? 'Você') : 'Robô $index',
            team: index % 2,
            connected: true,
            photoUrl: index == 0
                ? playerPhotoUrl
                : botAvatarAsset(botAvatars[index - 1]),
          ),
        ),
      );
    }

    final preferences = await SharedPreferences.getInstance();
    final savedTable = preferences.getString(tableNumberKey);
    final savedToken = preferences.getString(playerTokenKey);
    final response = await _client
        .post(
          Uri.parse('$serverUrl/api/tables/$tableNumber/join'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            if (savedTable == '$tableNumber' && savedToken != null)
              'playerToken': savedToken,
            'firebaseIdToken': firebaseIdToken,
            'playerName': playerName,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
          payload['error'] as String? ?? 'Não foi possível entrar na mesa.');
    }
    final entry = TableEntry.fromJson(serverUrl, payload);
    await preferences.setString(tableNumberKey, entry.tableNumber);
    await preferences.setString(playerTokenKey, entry.playerToken);
    await preferences.setInt(seatIndexKey, entry.seatIndex);
    return entry;
  }

  Future<TableEntry> watchTable(int tableNumber) async {
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
    final preferences = await SharedPreferences.getInstance();
    final tableNumber = preferences.getString(tableNumberKey);
    final playerToken = preferences.getString(playerTokenKey);
    if (tableNumber == null || playerToken == null) return null;
    return SavedTableSession(
      tableNumber: tableNumber,
      playerToken: playerToken,
    );
  }

  Future<bool> canResume(SavedTableSession session) async {
    if (!enabled) return false;
    final response = await _client
        .post(
          Uri.parse(
            '$serverUrl/api/tables/${session.tableNumber}/can-resume',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'playerToken': session.playerToken}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return false;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['canResume'] == true;
  }

  Future<void> declineResume(SavedTableSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pendingDeclineTableKey, session.tableNumber);
    await preferences.setString(_pendingDeclineTokenKey, session.playerToken);
    await clearSavedSession();
    await flushPendingDecline();
  }

  Future<void> flushPendingDecline() async {
    if (!enabled) return;
    final preferences = await SharedPreferences.getInstance();
    final tableNumber = preferences.getString(_pendingDeclineTableKey);
    final playerToken = preferences.getString(_pendingDeclineTokenKey);
    if (tableNumber == null || playerToken == null) return;
    try {
      final response = await _client
          .post(
            Uri.parse('$serverUrl/api/tables/$tableNumber/decline-resume'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerToken': playerToken}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      await Future.wait([
        preferences.remove(_pendingDeclineTableKey),
        preferences.remove(_pendingDeclineTokenKey),
      ]);
    } on Object {
      // A recusa permanece salva e serÃ¡ reenviada na prÃ³xima atualizaÃ§Ã£o.
    }
  }

  Future<void> clearSavedSession() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(tableNumberKey),
      preferences.remove(playerTokenKey),
      preferences.remove(seatIndexKey),
    ]);
  }

  void dispose() {
    final channel = _lobbyChannel;
    _lobbyChannel = null;
    if (channel != null) unawaited(channel.sink.close());
    _client.close();
  }

  static List<LobbyTable> _localTables() => List.generate(
        10,
        (index) => LobbyTable(
          tableNumber: index + 1,
          phase: LobbyTablePhase.empty,
          playerCount: 0,
          humanCount: 0,
          botCount: 0,
          capacity: 6,
          seats: List.filled(6, null),
        ),
      );
}
