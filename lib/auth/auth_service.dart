import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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
    await _persistenceReady;
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    final credential = await _auth.signInWithPopup(provider);
    await _ensureDefaultAvatar(credential.user);
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
