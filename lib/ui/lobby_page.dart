import 'dart:async';
import 'dart:typed_data';

import 'package:dourada/auth/auth_service.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/platform/fullscreen.dart';
import 'package:dourada/ui/game_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

typedef ProfileImagePicker = Future<SelectedProfileImage?> Function();

class LobbyPage extends StatefulWidget {
  const LobbyPage({
    super.key,
    this.service,
    this.authService,
    this.profileImagePicker,
  });

  final LobbyService? service;
  final AuthService? authService;
  final ProfileImagePicker? profileImagePicker;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  late final LobbyService _service;
  late final AuthService _authService;
  late final bool _ownsAuthService;
  StreamSubscription<List<LobbyTable>>? _lobbySubscription;
  Timer? _reconnectTimer;
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
  int? _openingTable;
  String? _error;
  bool _loading = false;
  bool _resumeOfferHandled = false;
  bool _resumeDialogOpen = false;
  bool _authBusy = false;
  bool _hasLobbySnapshot = false;
  SavedTableSession? _savedSession;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LobbyService();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? createAuthService();
    _authService.addListener(_onAuthChanged);
    unawaited(_connectLobby());
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {});
    if (_authService.currentUser != null &&
        !_resumeOfferHandled &&
        !_resumeDialogOpen &&
        _savedSession != null) {
      unawaited(_receiveTables(_tables));
    }
  }

  Future<void> _signIn() async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      await _authService.signInWithGoogle();
    } on Object catch (error) {
      if (mounted) _showAuthError(error);
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

  Future<void> _connectLobby() async {
    if (_loading) return;
    _reconnectTimer?.cancel();
    _loading = true;
    try {
      await _service.flushPendingDecline();
      _savedSession ??= await _service.savedSession();
      await _lobbySubscription?.cancel();
      if (!mounted) return;
      _lobbySubscription = _service.watchTables().listen(
            (tables) => unawaited(_receiveTables(tables)),
            onError: (_, __) => _handleLobbyDisconnected(),
            onDone: _handleLobbyDisconnected,
            cancelOnError: true,
          );
    } on Object {
      _handleLobbyDisconnected();
    } finally {
      _loading = false;
    }
  }

  Future<void> _receiveTables(List<LobbyTable> tables) async {
    if (!mounted) return;
    setState(() {
      _tables = tables;
      _error = null;
      _hasLobbySnapshot = true;
    });
    final savedSession = _savedSession;
    if (_authService.currentUser != null &&
        !_resumeOfferHandled &&
        !_resumeDialogOpen &&
        savedSession != null) {
      await _offerResume(savedSession, tables);
    }
  }

  void _handleLobbyDisconnected() {
    if (!mounted || !_service.enabled) return;
    setState(() {
      _error = 'Conexão com o lobby interrompida. Reconectando...';
      _hasLobbySnapshot = false;
    });
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(_connectLobby()),
    );
  }

  Future<void> _offerResume(
    SavedTableSession savedSession,
    List<LobbyTable> tables,
  ) async {
    _resumeDialogOpen = true;
    try {
      final tableNumber = int.tryParse(savedSession.tableNumber);
      final table = tableNumber == null
          ? null
          : tables.where((item) => item.tableNumber == tableNumber).firstOrNull;
      final valid = table != null &&
          table.phase != LobbyTablePhase.empty &&
          await _service.canResume(savedSession);
      if (!mounted) return;
      if (!valid) {
        _resumeOfferHandled = true;
        _savedSession = null;
        await _service.clearSavedSession();
        return;
      }

      _resumeOfferHandled = true;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final resume = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ResumeTableDialog(
              tableNumber: table.tableNumber,
              robotIsPlaying: table.phase == LobbyTablePhase.playing,
            ),
          ) ??
          false;
      if (!mounted) return;
      if (resume) {
        await _enter(table);
      } else {
        await _service.declineResume(savedSession);
        _savedSession = null;
        if (mounted) setState(() {});
      }
    } finally {
      _resumeDialogOpen = false;
    }
  }

  Future<void> _enter(LobbyTable table) async {
    if (_openingTable != null) return;
    if (_authService.currentUser == null) {
      await _signIn();
      return;
    }
    setState(() => _openingTable = table.tableNumber);
    // Deve acontecer antes das chamadas ao Firebase e à Cloudflare: o
    // navegador só permite fullscreen enquanto o clique ainda está ativo.
    await enterGameFullscreen();
    final profile = _authService.currentUser!;
    final lobbySubscription = _lobbySubscription;
    _lobbySubscription = null;
    if (lobbySubscription != null) {
      unawaited(lobbySubscription.cancel());
    }
    try {
      final firebaseIdToken = await _authService.idToken();
      final entry = await _service.joinTable(
        table.tableNumber,
        firebaseIdToken: firebaseIdToken,
        playerName: profile.displayName,
        playerPhotoUrl: profile.photoUrl,
      );
      if (!mounted) return;
      _resumeOfferHandled = true;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GamePage(entry: entry)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      await exitGameFullscreen();
      if (mounted) {
        setState(() => _openingTable = null);
        unawaited(_connectLobby());
      }
    }
  }

  Future<void> _watch(LobbyTable table) async {
    if (_openingTable != null || table.phase != LobbyTablePhase.playing) return;
    setState(() => _openingTable = table.tableNumber);
    await enterGameFullscreen();
    final lobbySubscription = _lobbySubscription;
    _lobbySubscription = null;
    if (lobbySubscription != null) {
      unawaited(lobbySubscription.cancel());
    }
    try {
      final entry = await _service.watchTable(table.tableNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GamePage(entry: entry)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      await exitGameFullscreen();
      if (mounted) {
        setState(() => _openingTable = null);
        unawaited(_connectLobby());
      }
    }
  }

  Future<void> _quickEnter() async {
    if (_openingTable != null || _authBusy || !_hasLobbySnapshot) return;
    if (_authService.currentUser == null) {
      await _signIn();
      return;
    }
    final table = selectQuickJoinTable(_tables);
    if (table == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma mesa livre no momento.')),
      );
      return;
    }
    await _enter(table);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    unawaited(_lobbySubscription?.cancel());
    _authService.removeListener(_onAuthChanged);
    if (_ownsAuthService) _authService.dispose();
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
                        Text('DOURADA',
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
                  if (_authService.currentUser != null)
                    IconButton(
                      key: const ValueKey('sair-conta'),
                      tooltip: 'Sair da conta',
                      onPressed: _authBusy ? null : _signOut,
                      color: Colors.white,
                      icon: _authBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.logout_rounded),
                    ),
                  const SizedBox(width: 4),
                  AuthAccountButton(
                    profile: _authService.currentUser,
                    busy: _authBusy,
                    available: _authService.available,
                    onLogin: _signIn,
                    onProfile: _openProfile,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('entrar-rapido'),
                      onPressed: _openingTable != null ||
                              _authBusy ||
                              !_hasLobbySnapshot
                          ? null
                          : _quickEnter,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE7A93E),
                        foregroundColor: const Color(0xFF173326),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      icon: _openingTable != null || !_hasLobbySnapshot
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_rounded),
                      label: Text(
                        !_hasLobbySnapshot
                            ? 'CARREGANDO MESAS...'
                            : _openingTable == null
                                ? 'ENTRAR RÁPIDO'
                                : 'ENTRANDO NA MESA $_openingTable...',
                      ),
                    ),
                  ),
                ),
              ),
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
                                : constraints.maxWidth >= 520
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
                            final requiresLogin =
                                _authService.currentUser == null;
                            return _TableCard(
                              table: table,
                              opening: _openingTable == table.tableNumber ||
                                  _authBusy,
                              requiresLogin: requiresLogin,
                              onEnter: table.canJoin
                                  ? requiresLogin
                                      ? _signIn
                                      : () => _enter(table)
                                  : null,
                              onWatch: table.canWatch ? () => _watch(table) : null,
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

class AuthAccountButton extends StatelessWidget {
  const AuthAccountButton({
    super.key,
    required this.profile,
    required this.busy,
    required this.available,
    required this.onLogin,
    required this.onProfile,
  });

  final AuthProfile? profile;
  final bool busy;
  final bool available;
  final VoidCallback onLogin;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final user = profile;
    if (user != null) {
      return Tooltip(
        message: 'Minha conta',
        child: InkWell(
          key: const ValueKey('abrir-perfil'),
          onTap: busy ? null : onProfile,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: UserAvatar(profile: user, radius: 20),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const ValueKey('entrar-conta'),
      onPressed: busy || !available ? null : onLogin,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFFFD46B),
        side: const BorderSide(color: Color(0x99FFD46B)),
        visualDensity: VisualDensity.compact,
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login_rounded, size: 18),
      label: const Text('LOGIN'),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    this.radius = 28,
    this.imageBytes,
    this.assetPath,
  });

  final AuthProfile profile;
  final double radius;
  final Uint8List? imageBytes;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.photoUrl.trim();
    final avatarAsset =
        assetPath ?? humanAvatarAssetFromPhotoUrl(profile.photoUrl);
    final fallback = _initials(profile.displayName, profile.email);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFE7A93E),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageBytes != null
          ? Image.memory(imageBytes!, fit: BoxFit.cover)
          : avatarAsset != null
              ? Transform.scale(
                  scale: 1.08,
                  child: Image.asset(avatarAsset, fit: BoxFit.cover),
                )
              : photoUrl.isEmpty
                  ? _AvatarInitials(text: fallback, fontSize: radius * .62)
                  : Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AvatarInitials(
                        text: fallback,
                        fontSize: radius * .62,
                      ),
                    ),
    );
  }

  static String _initials(String name, String email) {
    final source = name.trim().isEmpty ? email.split('@').first : name.trim();
    final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final letters = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF173326),
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

enum _ProfileImageAction { cameraOrPhotos }

class _ProfileImageSourceDialog extends StatefulWidget {
  const _ProfileImageSourceDialog({this.currentAvatarAsset});

  final String? currentAvatarAsset;

  @override
  State<_ProfileImageSourceDialog> createState() =>
      _ProfileImageSourceDialogState();
}

class _ProfileImageSourceDialogState extends State<_ProfileImageSourceDialog> {
  bool _showAvatars = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('dialogo-trocar-imagem'),
      backgroundColor: const Color(0xFF074333),
      title: Text(
        _showAvatars ? 'ESCOLHA UM AVATAR' : 'ALTERAR IMAGEM',
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: _showAvatars ? _buildAvatarPicker(context) : _buildSourcePicker(),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: _showAvatars
          ? [
              TextButton.icon(
                key: const ValueKey('voltar-escolha-imagem'),
                onPressed: () => setState(() => _showAvatars = false),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('VOLTAR'),
              ),
            ]
          : [
              TextButton.icon(
                key: const ValueKey('cancelar-escolha-imagem'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('CANCELAR'),
              ),
            ],
    );
  }

  Widget _buildSourcePicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('escolher-camera-fotos'),
            onPressed: () => Navigator.of(context).pop(
              _ProfileImageAction.cameraOrPhotos,
            ),
            icon: const Icon(Icons.photo_camera_rounded),
            label: const Text('CÂMERA / FOTOS'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('escolher-avatar'),
            onPressed: () => setState(() => _showAvatars = true),
            icon: const Icon(Icons.face_rounded),
            label: const Text('AVATAR'),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPicker(BuildContext context) {
    return SingleChildScrollView(
      child: Wrap(
        key: const ValueKey('lista-avatares-perfil'),
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var index = 0; index < profileAvatarAssets.length; index++)
            Tooltip(
              message: 'Avatar ${index + 1}',
              child: InkWell(
                key: ValueKey('escolher-avatar-perfil-$index'),
                onTap: () => Navigator.of(context).pop(
                  profileAvatarAssets[index],
                ),
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.currentAvatarAsset ==
                                      profileAvatarAssets[index]
                                  ? Colors.white70
                                  : Colors.white24,
                              width: widget.currentAvatarAsset ==
                                      profileAvatarAssets[index]
                                  ? 2
                                  : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Transform.scale(
                            scale: 1.08,
                            child: Image.asset(
                              profileAvatarAssets[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (widget.currentAvatarAsset ==
                          profileAvatarAssets[index])
                        Positioned(
                          right: -3,
                          bottom: -3,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF62DFA8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Color(0xFF052D22),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({
    super.key,
    required this.authService,
    this.imagePicker,
  });

  final AuthService authService;
  final ProfileImagePicker? imagePicker;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final TextEditingController _nameController;
  SelectedProfileImage? _selectedImage;
  String? _selectedAvatarAsset;
  bool _saving = false;
  bool _selectingImage = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.authService.currentUser!;
    _nameController = TextEditingController(text: profile.displayName);
    _nameController.addListener(_profileChanged);
  }

  void _profileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.authService.updateProfile(
        displayName: _nameController.text,
        image: _selectedImage,
        avatarAsset: _selectedAvatarAsset,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(readableAuthError(error))),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _changeProfileImage() async {
    if (_saving || _selectingImage) return;
    final profile = widget.authService.currentUser;
    if (profile == null) return;
    final currentAvatarAsset = _selectedImage == null
        ? _selectedAvatarAsset ?? humanAvatarAssetFromPhotoUrl(profile.photoUrl)
        : null;
    final choice = await showDialog<Object?>(
      context: context,
      builder: (_) => _ProfileImageSourceDialog(
        currentAvatarAsset: currentAvatarAsset,
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _ProfileImageAction.cameraOrPhotos) {
      await _selectImage();
      return;
    }
    if (choice is String) _selectAvatar(choice);
  }

  Future<void> _selectImage() async {
    if (_saving || _selectingImage) return;
    setState(() => _selectingImage = true);
    try {
      final image = await (widget.imagePicker ?? _pickProfileImage)();
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
          _selectedAvatarAsset = null;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(readableAuthError(error))),
      );
    } finally {
      if (mounted) setState(() => _selectingImage = false);
    }
  }

  void _selectAvatar(String assetPath) {
    if (_saving || _selectingImage) return;
    setState(() {
      _selectedAvatarAsset = assetPath;
      _selectedImage = null;
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_profileChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.authService.currentUser;
    if (profile == null) return const SizedBox.shrink();
    final preview = AuthProfile(
      uid: profile.uid,
      email: profile.email,
      displayName: _nameController.text,
      photoUrl: profile.photoUrl,
    );
    return AlertDialog(
      backgroundColor: const Color(0xFF074333),
      title: const Text('MINHA CONTA', textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    profile: preview,
                    radius: 46,
                    imageBytes: _selectedImage?.bytes,
                    assetPath: _selectedAvatarAsset,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Material(
                      color: const Color(0xFFE7A93E),
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: IconButton(
                        key: const ValueKey('trocar-foto-perfil'),
                        tooltip: 'Alterar imagem',
                        onPressed:
                            _saving || _selectingImage ? null : _changeProfileImage,
                        color: const Color(0xFF173326),
                        icon: _selectingImage
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _selectedImage != null
                    ? 'Nova foto selecionada.'
                    : _selectedAvatarAsset != null
                        ? 'Novo avatar selecionado.'
                        : 'Toque na câmera para alterar sua imagem.',
                style: TextStyle(color: Colors.white.withValues(alpha: .65)),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('nome-perfil'),
                controller: _nameController,
                enabled: !_saving,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Nome do jogador',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const ValueKey('email-perfil'),
                initialValue: profile.email,
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  helperText: 'O e-mail não pode ser alterado aqui.',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          key: const ValueKey('cancelar-perfil'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          label: const Text('CANCELAR'),
        ),
        FilledButton.icon(
          key: const ValueKey('salvar-perfil'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('SALVAR'),
        ),
      ],
    );
  }
}

Future<SelectedProfileImage?> _pickProfileImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes > 3 * 1024 * 1024) {
    throw ArgumentError('Escolha uma imagem de até 3 MB.');
  }
  final contentType = _imageContentType(file.name, file.mimeType);
  if (contentType == null) {
    throw ArgumentError('O arquivo escolhido precisa ser uma imagem.');
  }
  return SelectedProfileImage(bytes: bytes, contentType: contentType);
}

String? _imageContentType(String fileName, String? reportedType) {
  final normalizedType = reportedType?.toLowerCase();
  if (normalizedType?.startsWith('image/') == true) return normalizedType;
  final lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lowerName.endsWith('.png')) return 'image/png';
  if (lowerName.endsWith('.webp')) return 'image/webp';
  if (lowerName.endsWith('.gif')) return 'image/gif';
  return null;
}

String readableAuthError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'popup-closed-by-user' || 'cancelled-popup-request' => 'Login cancelado.',
      'popup-blocked' =>
        'O navegador bloqueou a janela de login. Permita pop-ups e tente novamente.',
      'unauthorized-domain' =>
        'Este endereço ainda não foi autorizado no Firebase Auth.',
      'operation-not-allowed' =>
        'O login com Google ainda não foi habilitado no Firebase Auth.',
      'network-request-failed' =>
        'Falha de conexão durante o login. Tente novamente.',
      _ => error.message ?? 'Não foi possível concluir a autenticação.',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'unauthorized' => 'Não foi permitido salvar a foto. Entre novamente.',
      'retry-limit-exceeded' =>
        'O envio da foto demorou demais. Tente novamente.',
      'canceled' => 'O envio da foto foi cancelado.',
      _ => error.message ?? 'Não foi possível salvar a foto.',
    };
  }
  return error
      .toString()
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Unsupported operation: ', '');
}

class _LobbySeatAvatar extends StatelessWidget {
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

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.opening,
    required this.requiresLogin,
    required this.onEnter,
    required this.onWatch,
    this.firstButtonKey,
  });

  final LobbyTable table;
  final bool opening;
  final bool requiresLogin;
  final VoidCallback? onEnter;
  final VoidCallback? onWatch;
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
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(status,
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              if (table.phase == LobbyTablePhase.playing) ...[
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: ValueKey('ver-mesa-${table.tableNumber}'),
                  onPressed: opening ? null : onWatch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: .8)),
                    backgroundColor: color.withValues(alpha: .08),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: opening
                      ? const SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_rounded, size: 15),
                  label: const Text('VER'),
                ),
              ],
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
              return _LobbySeatAvatar(
                key: ValueKey('avatar-mesa-${table.tableNumber}-$index'),
                seat: seat,
                teamColor: teamColor,
              );
            }),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: firstButtonKey,
              onPressed: opening || table.phase == LobbyTablePhase.playing
                  ? null
                  : onEnter,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE7A93E),
                foregroundColor: const Color(0xFF173326),
              ),
              child: opening && table.phase != LobbyTablePhase.playing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(requiresLogin
                      ? 'FAÇA LOGIN PARA ENTRAR'
                      : 'ENTRAR'),
            ),
          ),
        ],
      ),
    );
  }
}

class ResumeTableDialog extends StatefulWidget {
  const ResumeTableDialog({
    super.key,
    required this.tableNumber,
    this.robotIsPlaying = true,
  });

  final int tableNumber;
  final bool robotIsPlaying;

  @override
  State<ResumeTableDialog> createState() => _ResumeTableDialogState();
}

class _ResumeTableDialogState extends State<ResumeTableDialog> {
  static const _totalSeconds = 20;
  Timer? _timer;
  int _secondsLeft = _totalSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF074333),
        icon: const Icon(
          Icons.chair_rounded,
          color: Color(0xFFFFC857),
          size: 42,
        ),
        title: Text(
          'VOLTAR PARA A MESA ${widget.tableNumber}?',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.robotIsPlaying
                  ? 'Um robô está jogando na sua cadeira. Deseja assumir novamente?'
                  : 'Sua cadeira continua reservada. Deseja voltar para a mesa?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              key: const ValueKey('tempo-retomar-mesa'),
              value: _secondsLeft / _totalSeconds,
              minHeight: 7,
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFFC857),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 8),
            Text(
              'Fechando em $_secondsLeft ${_secondsLeft == 1 ? 'segundo' : 'segundos'}. '
              'Sem resposta: não voltar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: .65)),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            key: const ValueKey('nao-voltar-mesa'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('NÃO VOLTAR'),
          ),
          FilledButton.icon(
            key: const ValueKey('voltar-mesa'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.login_rounded),
            label: const Text('VOLTAR PARA A MESA'),
          ),
        ],
      ),
    );
  }
}
