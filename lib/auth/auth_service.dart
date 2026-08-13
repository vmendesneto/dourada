import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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
  }

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  late final Future<void> _persistenceReady;
  late final StreamSubscription<User?> _subscription;
  AuthProfile? _currentUser;

  @override
  AuthProfile? get currentUser => _currentUser;

  @override
  bool get available => true;

  @override
  Future<void> signInWithGoogle() async {
    await _persistenceReady;
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    await _auth.signInWithPopup(provider);
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

    var photoUrl = user.photoURL;
    if (image != null) {
      final photoReference =
          _storage.ref().child('profile_photos/${user.uid}/avatar');
      await photoReference.putData(
        image.bytes,
        SettableMetadata(contentType: image.contentType),
      );
      photoUrl = await photoReference.getDownloadURL();
    }
    await user.updateDisplayName(trimmedName);
    if (image != null) await user.updatePhotoURL(photoUrl);
    await user.reload();
    _currentUser = _profileFromUser(_auth.currentUser);
    notifyListeners();
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
  }) {
    throw UnsupportedError('O login esta disponivel na versao Web do jogo.');
  }
}
