import 'dart:async';

import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/ui/game_page.dart';
import 'package:flutter/material.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  late final LobbyService _service;
  Timer? _refreshTimer;
  List<LobbyTable> _tables = List.generate(
    10,
    (index) => LobbyTable(
      tableNumber: index + 1,
      phase: LobbyTablePhase.empty,
      playerCount: 0,
      humanCount: 0,
      botCount: 0,
      capacity: 6,
      seats: List<LobbySeat?>.filled(6, null),
    ),
  );
  String? _savedTable;
  int? _openingTable;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = LobbyService();
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object?>([
        _service.fetchTables(),
        _service.savedTableNumber(),
      ]);
      if (!mounted) return;
      setState(() {
        _tables = values[0] as List<LobbyTable>;
        _savedTable = values[1] as String?;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível atualizar as mesas.');
      }
    }
  }

  Future<void> _enter(LobbyTable table) async {
    if (_openingTable != null) return;
    setState(() => _openingTable = table.tableNumber);
    try {
      final entry = await _service.joinTable(table.tableNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GamePage(entry: entry)),
      );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } finally {
      if (mounted) setState(() => _openingTable = null);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF032C21),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFE7A93E),
                    foregroundColor: Color(0xFF173326),
                    child: Icon(Icons.style_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LOBBY DOURADINHA',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: const Color(0xFFFFD46B),
                                  fontWeight: FontWeight.w900,
                                )),
                        Text(
                            'Escolha uma das 10 mesas. Cada mesa tem 6 cadeiras.',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .7))),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar mesas',
                    onPressed: _load,
                    color: Colors.white,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFFF9E80))),
              ),
            Expanded(
              child: _tables.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1050
                            ? 5
                            : constraints.maxWidth >= 650
                                ? 3
                                : constraints.maxWidth >= 390
                                    ? 2
                                    : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 212,
                          ),
                          itemCount: _tables.length,
                          itemBuilder: (context, index) {
                            final table = _tables[index];
                            final resume =
                                _savedTable == '${table.tableNumber}';
                            return _TableCard(
                              table: table,
                              resume: resume,
                              opening: _openingTable == table.tableNumber,
                              onEnter: (table.canJoin || resume)
                                  ? () => _enter(table)
                                  : null,
                              firstButtonKey: index == 0
                                  ? const ValueKey('entrar-em-uma-mesa')
                                  : null,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.resume,
    required this.opening,
    required this.onEnter,
    this.firstButtonKey,
  });

  final LobbyTable table;
  final bool resume;
  final bool opening;
  final VoidCallback? onEnter;
  final Key? firstButtonKey;

  @override
  Widget build(BuildContext context) {
    final (status, color) = switch (table.phase) {
      LobbyTablePhase.empty => ('VAZIA', const Color(0xFF8FC7A4)),
      LobbyTablePhase.waiting => ('AGUARDANDO', const Color(0xFFFFC857)),
      LobbyTablePhase.playing => ('JOGANDO', const Color(0xFF69BFFF)),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF074333),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .72), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('MESA ${table.tableNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text('${table.playerCount}/6 jogadores',
              style: TextStyle(color: Colors.white.withValues(alpha: .72))),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            children: List.generate(6, (index) {
              final seat = table.seats[index];
              final teamColor = index.isEven
                  ? const Color(0xFF5CB6FF)
                  : const Color(0xFFFFC857);
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: seat == null
                      ? Colors.white.withValues(alpha: .05)
                      : teamColor.withValues(alpha: .15),
                  border: Border.all(
                    color: seat == null ? Colors.white24 : teamColor,
                  ),
                ),
                child: Icon(
                  seat == null
                      ? Icons.chair_outlined
                      : seat.isBot
                          ? Icons.smart_toy_rounded
                          : Icons.person_rounded,
                  color: seat == null ? Colors.white38 : teamColor,
                  size: 18,
                ),
              );
            }),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: firstButtonKey,
              onPressed: opening ? null : onEnter,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE7A93E),
                foregroundColor: const Color(0xFF173326),
              ),
              child: opening
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(resume
                      ? 'RETOMAR'
                      : table.phase == LobbyTablePhase.playing
                          ? 'SEM VAGA'
                          : 'ENTRAR EM UMA MESA'),
            ),
          ),
        ],
      ),
    );
  }
}
