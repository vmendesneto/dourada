import 'package:dourada/auth/auth_service.dart';

class FakeAuthService extends AuthService {
  FakeAuthService({bool signedIn = false}) {
    if (signedIn) _profile = _testProfile;
  }

  static const _testProfile = AuthProfile(
    uid: 'usuario-1',
    email: 'jogador@exemplo.com',
    displayName: 'Jogador',
    photoUrl: '',
  );

  AuthProfile? _profile;
  int signInCalls = 0;
  int signOutCalls = 0;
  int idTokenCalls = 0;
  int updateProfileCalls = 0;
  String? savedName;
  SelectedProfileImage? savedImage;
  String? savedAvatarAsset;

  @override
  bool get available => true;

  @override
  AuthProfile? get currentUser => _profile;

  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    _profile = _testProfile;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _profile = null;
    notifyListeners();
  }

  @override
  Future<String> idToken() async {
    idTokenCalls++;
    if (_profile == null) throw StateError('Usuário não autenticado.');
    return 'firebase-test-token';
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    SelectedProfileImage? image,
    String? avatarAsset,
  }) async {
    updateProfileCalls++;
    savedName = displayName;
    savedImage = image;
    savedAvatarAsset = avatarAsset;
    _profile = AuthProfile(
      uid: _profile!.uid,
      email: _profile!.email,
      displayName: displayName,
      photoUrl: image != null
          ? 'https://foto.salva/avatar'
          : avatarAsset != null
              ? humanAvatarPhotoUrl(avatarAsset)
              : _profile!.photoUrl,
    );
    notifyListeners();
  }
}
