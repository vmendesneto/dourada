import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> authNavigatorKey = GlobalKey<NavigatorState>();

const humanAvatarAssets = <String>[
  'assets/images/avatar/humanos/avatar_homem_01.png',
  'assets/images/avatar/humanos/avatar_homem_02.png',
  'assets/images/avatar/humanos/avatar_homem_03.png',
  'assets/images/avatar/humanos/avatar_homem_04.png',
  'assets/images/avatar/humanos/avatar_homem_05.png',
  'assets/images/avatar/humanos/avatar_homem_06.png',
  'assets/images/avatar/humanos/avatar_homem_07.png',
  'assets/images/avatar/humanos/avatar_homem_08.png',
  'assets/images/avatar/humanos/avatar_homem_09.png',
  'assets/images/avatar/humanos/avatar_homem_10.png',
  'assets/images/avatar/humanos/avatar_mulher_01.png',
  'assets/images/avatar/humanos/avatar_mulher_02.png',
  'assets/images/avatar/humanos/avatar_mulher_03.png',
  'assets/images/avatar/humanos/avatar_mulher_04.png',
  'assets/images/avatar/humanos/avatar_mulher_05.png',
  'assets/images/avatar/humanos/avatar_mulher_06.png',
  'assets/images/avatar/humanos/avatar_mulher_07.png',
  'assets/images/avatar/humanos/avatar_mulher_08.png',
  'assets/images/avatar/humanos/avatar_mulher_09.png',
  'assets/images/avatar/humanos/avatar_mulher_10.png',
];

// Estes arquivos têm fundo até as bordas e margem segura ao redor da cabeça,
// por isso funcionam corretamente dentro do recorte circular do perfil.
const profileAvatarAssets = <String>[
  'assets/images/avatar/humanos/avatar_homem_06.png',
  'assets/images/avatar/humanos/avatar_homem_07.png',
  'assets/images/avatar/humanos/avatar_homem_08.png',
  'assets/images/avatar/humanos/avatar_homem_09.png',
  'assets/images/avatar/humanos/avatar_homem_10.png',
  'assets/images/avatar/humanos/avatar_mulher_06.png',
  'assets/images/avatar/humanos/avatar_mulher_07.png',
  'assets/images/avatar/humanos/avatar_mulher_08.png',
  'assets/images/avatar/humanos/avatar_mulher_09.png',
  'assets/images/avatar/humanos/avatar_mulher_10.png',
];

const _humanAvatarPublicUrlPrefix =
    'https://vmendesneto.github.io/dourada/assets/assets/images/avatar/humanos/';

String humanAvatarPhotoUrl(String assetPath) {
  if (!humanAvatarAssets.contains(assetPath)) {
    throw ArgumentError('Avatar humano inválido.');
  }
  return '$_humanAvatarPublicUrlPrefix${assetPath.split('/').last}';
}

String? humanAvatarAssetFromPhotoUrl(String? photoUrl) {
  final normalized = photoUrl?.trim() ?? '';
  if (!normalized.startsWith(_humanAvatarPublicUrlPrefix)) return null;
  final fileName = normalized.substring(_humanAvatarPublicUrlPrefix.length);
  final assetPath = 'assets/images/avatar/humanos/$fileName';
  return humanAvatarAssets.contains(assetPath) ? assetPath : null;
}

String automaticHumanAvatarAsset(String uid) {
  var hash = 0;
  for (final value in uid.codeUnits) {
    hash = ((hash * 31) + value) & 0x7fffffff;
  }
  return profileAvatarAssets[hash % profileAvatarAssets.length];
}

class SelectedProfileImage {
  const SelectedProfileImage({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final String contentType;
}

class AuthProfile {
  const AuthProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
}

abstract class AuthService extends ChangeNotifier {
  AuthProfile? get currentUser;

  bool get available;

  Future<void> signInWithGoogle();

  Future<void> signOut();

  Future<String> idToken();

  Future<void> updateProfile({
    required String displayName,
    SelectedProfileImage? image,
    String? avatarAsset,
  });
}

AuthService createAuthService() {
  if (!kIsWeb || Firebase.apps.isEmpty) return DisabledAuthService();
  return FirebaseAuthService();
}

class FirebaseAuthService extends AuthService {
  FirebaseAuthService({FirebaseAuth? auth, FirebaseStorage? storage})
      : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance {
    _persistenceReady = _auth.setPersistence(Persistence.LOCAL);
    _currentUser = _profileFromUser(_auth.currentUser);
    _subscription = _auth.userChanges().listen((user) {
      _currentUser = _profileFromUser(user);
      notifyListeners();
    });
    unawaited(_assignInitialAvatar());
  }

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  late final Future<void> _persistenceReady;
  late final StreamSubscription<User?> _subscription;
  AuthProfile? _currentUser;
  bool _assigningDefaultAvatar = false;

  @override
  AuthProfile? get currentUser => _currentUser;

  @override
  bool get available => true;

  @override
  Future<void> signInWithGoogle() async {
    final context = authNavigatorKey.currentContext;
    if (context == null) {
      throw StateError('Não foi possível abrir o menu de login.');
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AuthMenu(authService: this),
    );
  }

  Future<void> _signInWithGoogleProvider() async {
    await _persistenceReady;
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    final credential = await _auth.signInWithPopup(provider);
    await _ensureDefaultAvatar(credential.user);
  }

  Future<void> _signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _persistenceReady;
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureDefaultAvatar(credential.user);
  }

  Future<void> _createAccount({
    required String email,
    required String password,
  }) async {
    await _persistenceReady;
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // O Firebase autentica automaticamente o usuário recém-criado.
    await _ensureDefaultAvatar(credential.user);
  }

  Future<void> _sendPasswordResetEmail(String email) async {
    await _persistenceReady;
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> idToken() async {
    await _persistenceReady;
    final user = _auth.currentUser;
    if (user == null) throw StateError('Entre na sua conta novamente.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Não foi possível confirmar sua autenticação.');
    }
    return token;
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    SelectedProfileImage? image,
    String? avatarAsset,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Entre na sua conta novamente.');

    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Informe um nome para o jogador.');
    }
    if (image != null && image.bytes.lengthInBytes > 3 * 1024 * 1024) {
      throw ArgumentError('Escolha uma imagem de até 3 MB.');
    }
    if (image != null && !image.contentType.startsWith('image/')) {
      throw ArgumentError('O arquivo escolhido precisa ser uma imagem.');
    }
    if (image != null && avatarAsset != null) {
      throw ArgumentError('Escolha uma foto ou um avatar, não os dois.');
    }
    if (avatarAsset != null && !humanAvatarAssets.contains(avatarAsset)) {
      throw ArgumentError('Escolha um avatar válido.');
    }

    var photoUrl = user.photoURL;
    if (image != null) {
      final photoReference =
          _storage.ref().child('profile_photos/${user.uid}/avatar');
      await photoReference.putData(
        image.bytes,
        SettableMetadata(contentType: image.contentType),
      );
      photoUrl = await photoReference.getDownloadURL();
    } else if (avatarAsset != null) {
      photoUrl = humanAvatarPhotoUrl(avatarAsset);
    }
    await user.updateDisplayName(trimmedName);
    if (image != null || avatarAsset != null) {
      await user.updatePhotoURL(photoUrl);
    }
    await user.reload();
    _currentUser = _profileFromUser(_auth.currentUser);
    notifyListeners();
  }

  Future<void> _assignInitialAvatar() async {
    try {
      await _persistenceReady;
      await _ensureDefaultAvatar(_auth.currentUser);
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Não foi possível definir o avatar: $error');
    }
  }

  Future<void> _ensureDefaultAvatar(User? user) async {
    if (user == null ||
        (user.photoURL?.trim().isNotEmpty ?? false) ||
        _assigningDefaultAvatar) {
      return;
    }
    _assigningDefaultAvatar = true;
    try {
      final avatarAsset = automaticHumanAvatarAsset(user.uid);
      await user.updatePhotoURL(humanAvatarPhotoUrl(avatarAsset));
      await user.reload();
      _currentUser = _profileFromUser(_auth.currentUser);
      notifyListeners();
    } finally {
      _assigningDefaultAvatar = false;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  static AuthProfile? _profileFromUser(User? user) {
    if (user == null) return null;
    return AuthProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName?.trim() ?? '',
      photoUrl: user.photoURL?.trim() ?? '',
    );
  }
}

class _AuthMenu extends StatefulWidget {
  const _AuthMenu({required this.authService});

  final FirebaseAuthService authService;

  @override
  State<_AuthMenu> createState() => _AuthMenuState();
}

class _AuthMenuState extends State<_AuthMenu>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmController = TextEditingController();
  bool _forgotPassword = false;
  bool _busy = false;
  bool _hideLoginPassword = true;
  bool _hideRegisterPassword = true;
  bool _hideRegisterConfirm = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmController.dispose();
    super.dispose();
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Informe seu e-mail.';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Informe um e-mail válido.';
    }
    return null;
  }

  void _setMessage(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _loginWithEmail() async {
    if (_busy) return;
    final emailError = _validateEmail(_loginEmailController.text);
    if (emailError != null) {
      _setMessage(emailError);
      return;
    }
    if (_loginPasswordController.text.isEmpty) {
      _setMessage('Informe sua senha.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.authService._signInWithEmail(
        email: _loginEmailController.text,
        password: _loginPasswordController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      _setMessage(_readableLoginError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.authService._signInWithGoogleProvider();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      _setMessage(_readableLoginError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    final emailError = _validateEmail(_registerEmailController.text);
    if (emailError != null) {
      _setMessage(emailError);
      return;
    }
    if (_registerPasswordController.text.isEmpty) {
      _setMessage('Informe uma senha.');
      return;
    }
    if (_registerPasswordController.text != _registerConfirmController.text) {
      _setMessage('A confirmação de senha não confere.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.authService._createAccount(
        email: _registerEmailController.text,
        password: _registerPasswordController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      _setMessage(_readableLoginError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_busy) return;
    final emailError = _validateEmail(_loginEmailController.text);
    if (emailError != null) {
      _setMessage(emailError);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.authService
          ._sendPasswordResetEmail(_loginEmailController.text);
      _setMessage(
        'E-mail de redefinição enviado. Confira sua caixa de entrada.',
        error: false,
      );
    } on Object catch (error) {
      _setMessage(_readableLoginError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: const OutlineInputBorder(),
    );
  }

  Widget _messageWidget() {
    final message = _message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (_messageIsError
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFF62DFA8))
              .withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _messageIsError
                ? const Color(0xFFFF8A80)
                : const Color(0xFF62DFA8),
          ),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _messageIsError
                ? const Color(0xFFFFB4AB)
                : const Color(0xFF8FE9C2),
          ),
        ),
      ),
    );
  }

  Widget _loginTab() {
    if (_forgotPassword) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 18),
          const Text(
            'REDEFINIR SENHA',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Informe o e-mail da sua conta e enviaremos o link de redefinição.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: .7)),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('login-email-reset'),
            controller: _loginEmailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: _fieldDecoration(
              label: 'E-mail',
              icon: Icons.email_outlined,
            ),
            onSubmitted: (_) => _sendPasswordReset(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('enviar-redefinicao-senha'),
              onPressed: _busy ? null : _sendPasswordReset,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('ENVIAR'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _forgotPassword = false;
                        _message = null;
                      }),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Voltar para o login'),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('login-email'),
          controller: _loginEmailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _fieldDecoration(
            label: 'E-mail',
            icon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('login-senha'),
          controller: _loginPasswordController,
          enabled: !_busy,
          obscureText: _hideLoginPassword,
          autofillHints: const [AutofillHints.password],
          decoration: _fieldDecoration(
            label: 'Senha',
            icon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              tooltip: _hideLoginPassword ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: _busy
                  ? null
                  : () => setState(
                        () => _hideLoginPassword = !_hideLoginPassword,
                      ),
              icon: Icon(
                _hideLoginPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          onSubmitted: (_) => _loginWithEmail(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('esqueci-senha'),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _forgotPassword = true;
                      _message = null;
                    }),
            child: const Text('Esqueci a senha'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('entrar-email-senha'),
            onPressed: _busy ? null : _loginWithEmail,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('ENTRAR'),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'ou',
                style: TextStyle(color: Colors.white.withValues(alpha: .6)),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('entrar-google'),
            onPressed: _busy ? null : _loginWithGoogle,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1F1F1F),
              disabledBackgroundColor: const Color(0xFFF2F2F2),
              disabledForegroundColor: const Color(0xFF747775),
              side: const BorderSide(color: Color(0xFF747775)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: Image.memory(
              UriData.parse(
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAABmJLR0QA/wD/AP+gvaeTAAADHElEQVRIia2US2yUVRTHf+fOVzPQlqbtfAMJKm1MNCWhUTsNQuwY24nRnSkUBxKCa+sjBqPRsJiIiiQ+IwsTdUXQtmOiiRotmRZSVsyUxoXAQqE+MfSl6BAKM3OPC3Ay/fy+zjRydvd/7/n97+scYZlYSHTdXrShnRjiqHYCrYBF5HdUz4noaMmYz9cdzU4HMcRPvNB7z4YQzmsiJAGz3CaAIsJhB5tqyZz6uarBbG9sp4q8D6ypAvaS/hBkt5vJflUpL9ndbCL2rIocWTEcQGlGNemVywYzfd2PqcqbBFybwoKInFTIAvM+80ciLW2P+xrMP9R9G8iHAfBRkHi0J+e6mex9a8dym92eXFSt3o/o0X/h0Za2PZJOl7zJAjC3u+OQvdAw6JmzorrXHZ98x+9EN8Ay2xfb5ra0f+YHB5Arx8JtTql0dnEqcvLK6K3xilO8FB3LHQiC1xrGKRaTQDh879wDTU+cmZRwMQ9MuT25g/8XDmDAPFgeNF3rbn7m9Ezojr9elxT2ZhhIIeP8CrK+QlOnWIjIwyz4JfS+mtea4apJAxLx6PNB8JWGguvXBqq1hppDjKw2oHMevVkztN4kj4sOmO9Ay2/wQ6lx+sClzgQcHw5ICvpdjwCdSxThohQyzvMgBwHSi+2Tb+c3dSh8325MLL3Dv3i8kUqpmai7fAa4q0K2tmDXGkec4aKaxcFLWyfeym+KKdQDd5/X0ou1wAEmbrm8xwNH0Ozx1Jo5I32LP21b6PtoqhCJL1mg8nLXcP/eavDE/nwC5ZBXV/j4uhGwZWRgfcHas0CjD2MMlVfaQ3Ki8so2jwxstNY+Gbp658ZVv72wVdSpq4BPhxvrO75+Wq6Wu2fsk/7tiIwQ0K6BPwXOKVgRNqgSLZ/Wrj7d8Mv+VilG1gEWlUfH99V/gRfWNdT/lCDvLmMSHCrzq2YGf6z7u3tofF/DG2Vz77quoe0Dgn4ANK3Q4pqxznPZXcPvVYr/qdpTyU/TakwncBio6Zsi8o2iW7xwqHIVNx5/l0JcrheRC6jCjBE5b7HHjIS+zO1IfxvE+AelUhzpSF0ykQAAAABJRU5ErkJggg==',
              ).contentAsBytes(),
              width: 20,
              height: 20,
              filterQuality: FilterQuality.high,
            ),
            label: const Text('Entrar com Google'),
          ),
        ),
      ],
    );
  }

  Widget _registerTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('cadastro-email'),
          controller: _registerEmailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
          decoration: _fieldDecoration(
            label: 'E-mail',
            icon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('cadastro-senha'),
          controller: _registerPasswordController,
          enabled: !_busy,
          obscureText: _hideRegisterPassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _fieldDecoration(
            label: 'Senha',
            icon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              tooltip:
                  _hideRegisterPassword ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: _busy
                  ? null
                  : () => setState(
                        () => _hideRegisterPassword = !_hideRegisterPassword,
                      ),
              icon: Icon(
                _hideRegisterPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('cadastro-confirmar-senha'),
          controller: _registerConfirmController,
          enabled: !_busy,
          obscureText: _hideRegisterConfirm,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _fieldDecoration(
            label: 'Confirmar senha',
            icon: Icons.lock_reset_rounded,
            suffixIcon: IconButton(
              tooltip: _hideRegisterConfirm ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: _busy
                  ? null
                  : () => setState(
                        () => _hideRegisterConfirm = !_hideRegisterConfirm,
                      ),
              icon: Icon(
                _hideRegisterConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          onSubmitted: (_) => _register(),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('cadastrar-email-senha'),
            onPressed: _busy ? null : _register,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('CADASTRAR'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 18, 16),
      backgroundColor: const Color(0xFF074333),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ACESSAR CONTA',
                        style: TextStyle(
                          color: Color(0xFFFFD46B),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  onTap: (_) => setState(() {
                    _forgotPassword = false;
                    _message = null;
                  }),
                  labelColor: const Color(0xFFFFD46B),
                  indicatorColor: const Color(0xFFE7A93E),
                  tabs: const [
                    Tab(text: 'LOGIN'),
                    Tab(text: 'CRIAR CONTA'),
                  ],
                ),
                const SizedBox(height: 12),
                _messageWidget(),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _tabController.index == 0
                        ? KeyedSubtree(
                            key: ValueKey(_forgotPassword
                                ? 'recuperar-senha'
                                : 'aba-login'),
                            child: _loginTab(),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('aba-criar-conta'),
                            child: _registerTab(),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _readableLoginError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'popup-closed-by-user' || 'cancelled-popup-request' => 'Login cancelado.',
      'popup-blocked' =>
        'O navegador bloqueou a janela do Google. Permita pop-ups e tente novamente.',
      'unauthorized-domain' =>
        'Este endereço ainda não foi autorizado no Firebase Auth.',
      'invalid-email' => 'Informe um e-mail válido.',
      'user-disabled' => 'Esta conta foi desativada.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'E-mail ou senha incorretos.',
      'email-already-in-use' => 'Já existe uma conta com este e-mail.',
      'weak-password' =>
        'A senha é muito fraca. Escolha uma senha com pelo menos 6 caracteres.',
      'too-many-requests' =>
        'Muitas tentativas em pouco tempo. Aguarde e tente novamente.',
      'operation-not-allowed' =>
        'Este método de autenticação ainda não foi habilitado no Firebase Auth.',
      'network-request-failed' =>
        'Falha de conexão durante a autenticação. Tente novamente.',
      _ => error.message ?? 'Não foi possível concluir a autenticação.',
    };
  }
  return error
      .toString()
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Unsupported operation: ', '');
}

class DisabledAuthService extends AuthService {
  @override
  bool get available => false;

  @override
  AuthProfile? get currentUser => null;

  @override
  Future<void> signInWithGoogle() {
    throw UnsupportedError('O login esta disponivel na versao Web do jogo.');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<String> idToken() {
    throw UnsupportedError('O login está disponível na versão Web do jogo.');
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    SelectedProfileImage? image,
    String? avatarAsset,
  }) {
    throw UnsupportedError('O login esta disponivel na versao Web do jogo.');
  }
}
