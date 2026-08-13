import 'package:dourada/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mantém os vinte avatares humanos com nomes padronizados', () {
    expect(humanAvatarAssets, hasLength(20));
    expect(humanAvatarAssets.toSet(), hasLength(20));
    expect(
      humanAvatarAssets.where((path) => path.contains('avatar_homem_')),
      hasLength(10),
    );
    expect(
      humanAvatarAssets.where((path) => path.contains('avatar_mulher_')),
      hasLength(10),
    );
  });

  test('atribui sempre o mesmo avatar automático para o mesmo usuário', () {
    final firstChoice = automaticHumanAvatarAsset('firebase-usuario-123');

    expect(automaticHumanAvatarAsset('firebase-usuario-123'), firstChoice);
    expect(profileAvatarAssets, hasLength(10));
    expect(profileAvatarAssets, contains(firstChoice));
  });

  test('converte o avatar salvo no Auth de volta para o asset local', () {
    final assetPath = humanAvatarAssets[13];
    final photoUrl = humanAvatarPhotoUrl(assetPath);

    expect(humanAvatarAssetFromPhotoUrl(photoUrl), assetPath);
    expect(
      humanAvatarAssetFromPhotoUrl('https://example.com/foto.png'),
      isNull,
    );
  });
}
