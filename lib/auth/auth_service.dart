import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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

  Future<void> updateProfile({
    required String displayName,
    required String photoUrl,
  });
}

AuthService createAuthService() {
  if (!kIsWeb || Firebase.apps.isEmpty) return DisabledAuthService();
  return FirebaseAuthService();
}

class FirebaseAuthService extends AuthService {
  FirebaseAuthService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance {
    _currentUser = _profileFromUser(_auth.currentUser);
    _subscription = _auth.userChanges().listen((user) {
      _currentUser = _profileFromUser(user);
      notifyListeners();
    });
  }

  final FirebaseAuth _auth;
  late final StreamSubscription<User?> _subscription;
  AuthProfile? _currentUser;

  @override
  AuthProfile? get currentUser => _currentUser;

  @override
  bool get available => true;

  @override
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    await _auth.signInWithPopup(provider);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateProfile({
    required String displayName,
    required String photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Entre na sua conta novamente.');

    final trimmedName = displayName.trim();
    final trimmedPhoto = photoUrl.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Informe um nome para o jogador.');
    }
    if (trimmedPhoto.isNotEmpty) {
      final uri = Uri.tryParse(trimmedPhoto);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw ArgumentError('Informe uma URL de imagem valida.');
      }
    }

    await user.updateDisplayName(trimmedName);
    await user.updatePhotoURL(trimmedPhoto.isEmpty ? null : trimmedPhoto);
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
  Future<void> updateProfile({
    required String displayName,
    required String photoUrl,
  }) {
    throw UnsupportedError('O login esta disponivel na versao Web do jogo.');
  }
}
