from pathlib import Path


def replace_once(path, old, new):
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'Trecho não encontrado em {path}')
    file.write_text(text.replace(old, new, 1))


lobby_path = 'lib/ui/lobby_page.dart'

old_seat = """              return Container(
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
              );"""

new_seat = """              return _LobbySeatAvatar(
                key: ValueKey('avatar-mesa-${table.tableNumber}-$index'),
                seat: seat,
                teamColor: teamColor,
              );"""
replace_once(lobby_path, old_seat, new_seat)

marker = 'class _TableCard extends StatelessWidget {'
avatar_widget = """class _LobbySeatAvatar extends StatelessWidget {
  const _LobbySeatAvatar({
    super.key,
    required this.seat,
    required this.teamColor,
  });

  final LobbySeat? seat;
  final Color teamColor;

  @override
  Widget build(BuildContext context) {
    final currentSeat = seat;
    if (currentSeat == null) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .05),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(
          Icons.chair_outlined,
          color: Colors.white38,
          size: 18,
        ),
      );
    }

    final photoUrl = currentSeat.photoUrl?.trim() ?? '';
    final assetPath = currentSeat.isBot
        ? (photoUrl.startsWith('assets/') ? photoUrl : null)
        : humanAvatarAssetFromPhotoUrl(photoUrl);
    final fallback = Icon(
      currentSeat.isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
      color: teamColor,
      size: 18,
    );

    return Tooltip(
      message: currentSeat.name,
      child: Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: teamColor.withValues(alpha: .15),
          border: Border.all(color: teamColor),
        ),
        child: ClipOval(
          child: photoUrl.isEmpty
              ? fallback
              : assetPath != null
                  ? Image.asset(
                      assetPath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    )
                  : Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    ),
        ),
      ),
    );
  }
}

"""
replace_once(lobby_path, marker, avatar_widget + marker)

test_path = 'test/widget_test.dart'
test_marker = "  testWidgets('entrada rápida escolhe a primeira mesa aguardando',"
avatar_test = """  testWidgets('lobby mostra as imagens dos humanos e dos robôs na mesa',
      (tester) async {
    final humanAsset = profileAvatarAssets.first;
    final botAsset = botAvatarAsset(1);
    final service = _HangingCancelLobbyService(
      tables: [
        LobbyTable(
          tableNumber: 1,
          phase: LobbyTablePhase.playing,
          playerCount: 2,
          humanCount: 1,
          botCount: 1,
          capacity: 6,
          seats: [
            LobbySeat(
              index: 0,
              kind: 'human',
              name: 'Ana',
              team: 0,
              connected: true,
              photoUrl: humanAvatarPhotoUrl(humanAsset),
            ),
            LobbySeat(
              index: 1,
              kind: 'bot',
              name: 'Robô 2',
              team: 1,
              connected: true,
              photoUrl: botAsset,
            ),
            ...List<LobbySeat?>.filled(4, null),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LobbyPage(
          service: service,
          authService: FakeAuthService(signedIn: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final humanAvatar = find.byKey(const ValueKey('avatar-mesa-1-0'));
    final botAvatar = find.byKey(const ValueKey('avatar-mesa-1-1'));
    expect(humanAvatar, findsOneWidget);
    expect(botAvatar, findsOneWidget);

    final humanImage = tester.widget<Image>(
      find.descendant(of: humanAvatar, matching: find.byType(Image)),
    );
    final botImage = tester.widget<Image>(
      find.descendant(of: botAvatar, matching: find.byType(Image)),
    );
    expect((humanImage.image as AssetImage).assetName, humanAsset);
    expect((botImage.image as AssetImage).assetName, botAsset);

    await tester.pumpWidget(const SizedBox.shrink());
  });

"""
replace_once(test_path, test_marker, avatar_test + test_marker)
