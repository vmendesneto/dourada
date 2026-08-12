import 'package:dourada/online/table_session.dart';
import 'package:dourada/ui/game_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  late final Future<String?> _savedTableNumber = _readSavedTableNumber();
  bool _openingTable = false;

  Future<String?> _readSavedTableNumber() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(TableSession.tableNumberKey);
  }

  Future<void> _enterTable() async {
    if (_openingTable) return;
    setState(() => _openingTable = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GamePage()),
    );
    if (mounted) setState(() => _openingTable = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.25,
            colors: [Color(0xFF12623F), Color(0xFF033929), Color(0xFF01251C)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _LobbyMark(),
                          const SizedBox(height: 22),
                          Text(
                            'DOURADINHA',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                  color: const Color(0xFFFFD46B),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Um humano, cinco robôs e dois trios na mesa.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .86),
                                ),
                          ),
                          const SizedBox(height: 26),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: const Color(0xFF062F25)
                                  .withValues(alpha: .92),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFD8A84E)
                                    .withValues(alpha: .7),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 24,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                const _PlayersPreview(),
                                const SizedBox(height: 20),
                                FutureBuilder<String?>(
                                  future: _savedTableNumber,
                                  builder: (context, snapshot) {
                                    final tableNumber = snapshot.data;
                                    return Text(
                                      tableNumber == null
                                          ? 'Uma nova mesa será criada somente depois que você entrar.'
                                          : 'Sua mesa $tableNumber será retomada se a partida ainda estiver acontecendo.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: .72),
                                          ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: FilledButton.icon(
                                    key: const ValueKey('entrar-em-uma-mesa'),
                                    onPressed:
                                        _openingTable ? null : _enterTable,
                                    icon: _openingTable
                                        ? const SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2.5),
                                          )
                                        : const Icon(Icons.login_rounded),
                                    label: const Text('ENTRAR EM UMA MESA'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFE7A93E),
                                      foregroundColor: const Color(0xFF1E291F),
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .8,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Se você sair durante a partida, um robô assume até você voltar.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .56),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LobbyMark extends StatelessWidget {
  const _LobbyMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE7A93E),
        border: Border.all(color: const Color(0xFFFFDF87), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x779A681B), blurRadius: 24)],
      ),
      child:
          const Icon(Icons.style_rounded, size: 40, color: Color(0xFF173326)),
    );
  }
}

class _PlayersPreview extends StatelessWidget {
  const _PlayersPreview();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: List.generate(6, (index) {
        final human = index == 0;
        final blueTeam = index.isEven;
        final color =
            blueTeam ? const Color(0xFF49B6FF) : const Color(0xFFFFC94F);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .16),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(
                human ? Icons.person_rounded : Icons.smart_toy_rounded,
                color: color,
                size: 25,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              human ? 'VOCÊ' : 'ROBÔ',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        );
      }),
    );
  }
}
