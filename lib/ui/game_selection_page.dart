import 'package:dourada/auth/auth_service.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/ui/lobby_page.dart';
import 'package:flutter/material.dart';

class GameSelectionPage extends StatefulWidget {
  const GameSelectionPage({
    super.key,
    this.authService,
    this.lobbyService,
    this.profileImagePicker,
  });

  final AuthService? authService;
  final LobbyService? lobbyService;
  final ProfileImagePicker? profileImagePicker;

  @override
  State<GameSelectionPage> createState() => _GameSelectionPageState();
}

class _GameSelectionPageState extends State<GameSelectionPage> {
  late final AuthService _authService;
  late final bool _ownsAuthService;
  bool _authBusy = false;
  bool _openingGame = false;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? createAuthService();
    _authService.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _signIn() async {
    if (_authBusy) return false;
    setState(() => _authBusy = true);
    try {
      await _authService.signInWithGoogle();
      return _authService.currentUser != null;
    } on Object catch (error) {
      if (mounted) _showAuthError(error);
      return false;
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      await _authService.signOut();
    } on Object catch (error) {
      if (mounted) _showAuthError(error);
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _openProfile() async {
    if (_authBusy || _authService.currentUser == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ProfileDialog(
        authService: _authService,
        imagePicker: widget.profileImagePicker,
      ),
    );
  }

  void _showAuthError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(readableAuthError(error))),
    );
  }

  Future<void> _openDouradaInterior() async {
    if (_openingGame || _authBusy) return;
    if (_authService.currentUser == null && !await _signIn()) return;
    if (!mounted) return;
    setState(() => _openingGame = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LobbyPage(
            service: widget.lobbyService,
            authService: _authService,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingGame = false);
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    if (_ownsAuthService) _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1EA),
      body: SafeArea(
        child: Column(
          children: [
            _SelectionHeader(
              profile: _authService.currentUser,
              busy: _authBusy,
              available: _authService.available,
              onLogin: _signIn,
              onProfile: _openProfile,
              onSignOut: _signOut,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escolha um jogo',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: const Color(0xFF173326),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selecione um card para entrar no lobby do jogo.',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: const Color(0xFF52665D),
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _GameCard(
                            key: const ValueKey('jogo-dourada-interior'),
                            busy: _openingGame || _authBusy,
                            onTap: _openDouradaInterior,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.profile,
    required this.busy,
    required this.available,
    required this.onLogin,
    required this.onProfile,
    required this.onSignOut,
  });

  final AuthProfile? profile;
  final bool busy;
  final bool available;
  final VoidCallback onLogin;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF032C21), Color(0xFF07513B)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFE7A93E),
                foregroundColor: Color(0xFF173326),
                child: Icon(Icons.style_rounded, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DOURADA',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFFFFD46B),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                    ),
                    Text(
                      'JOGOS DE CARTAS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              if (profile != null)
                IconButton(
                  key: const ValueKey('sair-conta'),
                  tooltip: 'Sair da conta',
                  onPressed: busy ? null : onSignOut,
                  color: Colors.white,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                ),
              const SizedBox(width: 4),
              AuthAccountButton(
                profile: profile,
                busy: busy,
                available: available,
                onLogin: onLogin,
                onProfile: onProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    super.key,
    required this.busy,
    required this.onTap,
  });

  static const _imageAsset =
      'assets/images/dourada_interior/dourada_interior.png';

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: Material(
        color: Colors.white,
        elevation: 5,
        shadowColor: const Color(0x44032C21),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('abrir-dourada-interior'),
          onTap: busy ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.45,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(_imageAsset, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x33000000)],
                          stops: [0.68, 1],
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 12,
                      top: 12,
                      child: _AvailableBadge(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dourada Interior',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: const Color(0xFF173326),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.groups_rounded,
                                size: 17,
                                color: Color(0xFF65776E),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '6 jogadores',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF65776E),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE7A93E),
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFF173326),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailableBadge extends StatelessWidget {
  const _AvailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6032C21),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, color: Color(0xFFFFD46B), size: 16),
          SizedBox(width: 3),
          Text(
            'JOGAR',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}
