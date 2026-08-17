from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: esperado 1 trecho, encontrado {count}")
    file.write_text(text.replace(old, new, 1))


# Dependência e assets de áudio.
pubspec = Path('pubspec.yaml')
text = pubspec.read_text()
text = text.replace(
    '  web: ^1.1.1\n',
    '  web: ^1.1.1\n  audioplayers: ^6.8.1\n',
    1,
)
text = text.replace(
    '    - assets/gifs/\n',
    '''    - assets/gifs/\n    - assets/sons/truco/\n    - assets/sons/seis/\n    - assets/sons/nove/\n    - assets/sons/doze/\n    - assets/sons/aceitar/\n    - assets/sons/correr/\n''',
    1,
)
pubspec.write_text(text)

# Player e catálogo de sons ficam no estado da tela para que tocar áudio seja
# um efeito do evento (uma vez), e não de rebuilds do widget.
replace_once(
    'lib/ui/game_page.dart',
    "import 'package:dourada/platform/fullscreen.dart';\n",
    "import 'package:dourada/platform/fullscreen.dart';\nimport 'package:audioplayers/audioplayers.dart';\n",
)

replace_once(
    'lib/ui/game_page.dart',
    "class _GamePageState extends State<GamePage> with WidgetsBindingObserver {\n  static const _savedGameKey = 'douradinha_partida_em_andamento_v1';\n",
    '''class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  static const _savedGameKey = 'douradinha_partida_em_andamento_v1';
  static const _challengeCallSounds = <int, List<String>>{
    2: [
      'sons/truco/truco.mp3',
      'sons/truco/truco_ladrao.mp3',
      'sons/truco/truco_rato.mp3',
    ],
    3: [
      'sons/seis/seis.mp3',
      'sons/seis/seis_e_seis.mp3',
      'sons/seis/seis_vale.mp3',
    ],
    4: [
      'sons/nove/nove.mp3',
      'sons/nove/nove_entao.mp3',
    ],
    6: [
      'sons/doze/doze_queda.mp3',
      'sons/doze/doze_rato.mp3',
      'sons/doze/doze_vale.mp3',
    ],
  };
  static const _acceptedChallengeSounds = <String>[
    'sons/aceitar/aceito.mp3',
    'sons/aceitar/cafe.mp3',
    'sons/aceitar/joga.mp3',
  ];
  static const _foldedChallengeSounds = <String>[
    'sons/correr/quero_nao.mp3',
    'sons/correr/to_fora.mp3',
    'sons/correr/vazei.mp3',
  ];
''',
)

replace_once(
    'lib/ui/game_page.dart',
    '''  late final DouradinhaGame game;
  late final TableSession tableSession;
  late final Future<SharedPreferences> _preferences;
''',
    '''  late final DouradinhaGame game;
  late final TableSession tableSession;
  late final AudioPlayer _challengeAudioPlayer;
  late final Future<SharedPreferences> _preferences;
  final math.Random _challengeSoundRandom = math.Random();
''',
)

replace_once(
    'lib/ui/game_page.dart',
    '''    tableSession = TableSession(entry: widget.entry)
      ..addListener(_onTableSessionChanged);
    _preferences = SharedPreferences.getInstance();
''',
    '''    tableSession = TableSession(entry: widget.entry)
      ..addListener(_onTableSessionChanged);
    _challengeAudioPlayer = AudioPlayer();
    _preferences = SharedPreferences.getInstance();
''',
)

replace_once(
    'lib/ui/game_page.dart',
    '''    tableSession
      ..removeListener(_onTableSessionChanged)
      ..dispose();
    game
''',
    '''    tableSession
      ..removeListener(_onTableSessionChanged)
      ..dispose();
    unawaited(
      _challengeAudioPlayer.dispose().catchError((Object _) {}),
    );
    game
''',
)

# Método único para tocar uma fala aleatória do cenário, sem loop. Se o áudio
# falhar ou o navegador bloquear autoplay, a partida continua normalmente.
replace_once(
    'lib/ui/game_page.dart',
    '''  void _syncChallengeNotice() {
''',
    '''  Future<void> _playChallengeSound(List<String> sounds) async {
    if (sounds.isEmpty) return;
    final asset = sounds[_challengeSoundRandom.nextInt(sounds.length)];
    try {
      await _challengeAudioPlayer.stop();
      await _challengeAudioPlayer.play(AssetSource(asset));
    } on Object {
      // Som é decorativo e nunca pode bloquear a partida.
    }
  }

  void _syncChallengeNotice() {
''',
)

replace_once(
    'lib/ui/game_page.dart',
    '''    _challengeNoticeStarted = true;
    _challengeNoticeVisible = true;
    _challengeNoticeTimer = Timer(
''',
    '''    _challengeNoticeStarted = true;
    _challengeNoticeVisible = true;
    unawaited(
      _playChallengeSound(
        game.challengeNoticeAccepted
            ? _acceptedChallengeSounds
            : _foldedChallengeSounds,
      ),
    );
    _challengeNoticeTimer = Timer(
''',
)

replace_once(
    'lib/ui/game_page.dart',
    '''    _activeChallengeAnimation = _challengeAnimationQueue.removeAt(0);
    _challengeAnimationTimer = Timer(
''',
    '''    _activeChallengeAnimation = _challengeAnimationQueue.removeAt(0);
    final sounds =
        _challengeCallSounds[_activeChallengeAnimation!.requestedValue];
    if (sounds != null) unawaited(_playChallengeSound(sounds));
    _challengeAnimationTimer = Timer(
''',
)
