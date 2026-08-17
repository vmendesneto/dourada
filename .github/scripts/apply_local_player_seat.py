from pathlib import Path
import re

path = Path('lib/ui/game_page.dart')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'trecho esperado uma vez, encontrado {count}: {old[:80]!r}')
    text = text.replace(old, new, 1)


replace_once(
    '''            if (!tableSession.isSpectator)\n              _HumanControls(\n                game: game,\n                clockActive: _clockPlayerIndex == game.humanPlayerIndex,\n                turnProgress: _turnProgress,\n                secondsLeft: _turnSecondsLeft,\n              ),\n''',
    '''            if (!tableSession.isSpectator) _HumanControls(game: game),\n''',
)

replace_once(
    '''        Widget botSeat(int playerIndex, Alignment alignment) => Align(\n''',
    '''        Widget botSeat(\n          int playerIndex,\n          Alignment alignment, {\n          bool showHand = true,\n        }) =>\n            Align(\n''',
)

replace_once(
    '''                  hiddenCardCount: spectator\n                      ? tableSession.spectatorHandCountFor(playerIndex)\n                      : 0,\n                ),\n''',
    '''                  hiddenCardCount: spectator\n                      ? tableSession.spectatorHandCountFor(playerIndex)\n                      : 0,\n                  showHand: showHand,\n                ),\n''',
)

replace_once(
    '''                    if (spectator)\n                      botSeat(game.humanPlayerIndex, const Alignment(0, 1)),\n''',
    '''                    botSeat(\n                      game.humanPlayerIndex,\n                      const Alignment(0, .90),\n                      showHand: spectator,\n                    ),\n''',
)

replace_once(
    '''    this.spectatorMode = false,\n    this.hiddenCardCount = 0,\n  });\n''',
    '''    this.spectatorMode = false,\n    this.hiddenCardCount = 0,\n    this.showHand = true,\n  });\n''',
)

replace_once(
    '''  final bool spectatorMode;\n  final int hiddenCardCount;\n''',
    '''  final bool spectatorMode;\n  final int hiddenCardCount;\n  final bool showHand;\n''',
)

replace_once(
    '''    final signalEmoji = game.signalEmojiFor(playerIndex);\n\n    return Stack(\n''',
    '''    final signalEmoji = game.signalEmojiFor(playerIndex);\n    final localSeat = playerIndex == game.humanPlayerIndex && !spectatorMode;\n\n    return Stack(\n''',
)

replace_once(
    '''                  _TablePlayerAvatar(\n                    key: ValueKey('avatar-jogador-$playerIndex'),\n''',
    '''                  _TablePlayerAvatar(\n                    key: localSeat\n                        ? const ValueKey('avatar-jogador-local')\n                        : ValueKey('avatar-jogador-$playerIndex'),\n''',
)

replace_once(
    '''                        child: Text(\n                          player.name,\n                          maxLines: 1,\n''',
    '''                        child: Text(\n                          player.name,\n                          key: localSeat\n                              ? const ValueKey('nome-jogador-local')\n                              : null,\n                          maxLines: 1,\n''',
)

replace_once(
    '''              ] else if (!spectatorMode && (!compact || reveal)) ...[\n''',
    '''              ] else if (showHand &&\n                  !spectatorMode &&\n                  (!compact || reveal)) ...[\n''',
)

new_human_controls = r'''class _HumanControls extends StatelessWidget {
  const _HumanControls({required this.game});

  final DouradinhaGame game;

  @override
  Widget build(BuildContext context) {
    final human = game.players[game.humanPlayerIndex];
    final active = game.isHumanTurn;
    final phone = MediaQuery.sizeOf(context).width < 600;

    Widget challengeButton({required double width, required double height}) {
      return SizedBox(
        width: width,
        height: height,
        child: FilledButton.icon(
          onPressed: game.canHumanChallenge ? game.requestHumanChallenge : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE9A23B),
            foregroundColor: const Color(0xFF271500),
            padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 12),
          ),
          icon: Icon(Icons.campaign, size: phone ? 17 : 20),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              game.challengeButtonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    Widget cards({required bool compact}) {
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final card in human.hand)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5),
                child: _PlayableCard(
                  card: card,
                  enabled: active,
                  hidden: game.isHumanCardHidden(card),
                  canToggleHidden: game.canHumanHideCard(card),
                  compact: compact,
                  onTap: () => game.playHumanCard(card),
                  onToggleHidden: () => game.toggleHumanCardHidden(card),
                ),
              ),
          ],
        ),
      );
    }

    if (phone) {
      return Container(
        key: const ValueKey('controles-jogador-local'),
        height: 101,
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: const BoxDecoration(
          color: Color(0xFF052D22),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Row(
          children: [
            cards(compact: true),
            const SizedBox(width: 6),
            challengeButton(width: 116, height: 42),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('controles-jogador-local'),
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFF052D22),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Row(
        children: [
          cards(compact: false),
          const SizedBox(width: 16),
          challengeButton(width: 150, height: 52),
        ],
      ),
    );
  }
}

'''

pattern = re.compile(
    r'class _HumanControls extends StatelessWidget \{.*?\n\}\n\n(?=class _TurnProgress extends StatelessWidget)',
    re.S,
)
text, count = pattern.subn(new_human_controls, text, count=1)
if count != 1:
    raise SystemExit(f'_HumanControls não encontrado uma vez: {count}')

path.write_text(text)
