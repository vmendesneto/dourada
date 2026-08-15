from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Trecho não encontrado: {label}')
    return text.replace(old, new, 1)


lobby_path = Path('lib/ui/lobby_page.dart')
lobby = lobby_path.read_text()

profile_marker = 'class ProfileDialog extends StatefulWidget {'
image_dialog = '''enum _ProfileImageAction { cameraOrPhotos }

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

'''
lobby = replace_once(lobby, profile_marker, image_dialog + profile_marker, 'dialogo de imagem')

select_image_marker = '  Future<void> _selectImage() async {'
change_image_method = '''  Future<void> _changeProfileImage() async {
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

'''
lobby = replace_once(
    lobby,
    select_image_marker,
    change_image_method + select_image_marker,
    'metodo de escolha de imagem',
)

old_current_avatar = '''    final currentAvatarAsset = _selectedImage == null
        ? _selectedAvatarAsset ?? humanAvatarAssetFromPhotoUrl(profile.photoUrl)
        : null;

'''
lobby = replace_once(lobby, old_current_avatar, '', 'avatar atual da tela principal')
lobby = replace_once(lobby, "tooltip: 'Escolher nova foto',", "tooltip: 'Alterar imagem',", 'tooltip')
lobby = replace_once(
    lobby,
    '_saving || _selectingImage ? null : _selectImage,',
    '_saving || _selectingImage ? null : _changeProfileImage,',
    'acao da camera',
)
lobby = replace_once(
    lobby,
    ": 'Clique na câmera ou escolha um avatar abaixo.',",
    ": 'Toque na câmera para alterar sua imagem.',",
    'texto de ajuda',
)

avatar_start = lobby.index(
    "              const SizedBox(height: 16),\n"
    "              Align(\n"
    "                alignment: Alignment.centerLeft,\n"
    "                child: Text(\n"
    "                  'ESCOLHA UM AVATAR',"
)
avatar_end = lobby.index(
    "              const SizedBox(height: 20),\n"
    "              TextField(",
    avatar_start,
)
lobby = lobby[:avatar_start] + lobby[avatar_end:]
lobby_path.write_text(lobby)


test_path = Path('test/widget_test.dart')
test = test_path.read_text()

photo_click = '''    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
'''
photo_choice = '''    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialogo-trocar-imagem')), findsOneWidget);
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('escolher-camera-fotos')));
    await tester.pumpAndSettle();
'''
if test.count(photo_click) < 2:
    raise SystemExit('Fluxos de foto esperados não encontrados')
test = test.replace(photo_click, photo_choice, 2)

first_avatar_prefix = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final avatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
'''
first_avatar_new = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('escolher-camera-fotos')), findsOneWidget);
    expect(find.byKey(const ValueKey('escolher-avatar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voltar-escolha-imagem')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    expect(find.byKey(const ValueKey('escolher-camera-fotos')), findsOneWidget);
    expect(find.byKey(const ValueKey('escolher-avatar')), findsOneWidget);
    expect(find.text('Novo avatar selecionado.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
    await tester.pumpAndSettle();
    final avatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
'''
test = replace_once(test, first_avatar_prefix, first_avatar_new, 'primeira escolha de avatar')

saved_avatar_prefix = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final savedAvatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
'''
saved_avatar_new = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
    await tester.pumpAndSettle();
    final savedAvatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
'''
test = replace_once(test, saved_avatar_prefix, saved_avatar_new, 'segunda escolha de avatar')
test_path.write_text(test)
