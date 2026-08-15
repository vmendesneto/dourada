from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'Trecho não encontrado em {path}')
    file.write_text(text.replace(old, new, 1))


lobby_path = 'lib/ui/lobby_page.dart'
text = Path(lobby_path).read_text()

avatar_initials_end = '''class _AvatarInitials extends StatelessWidget {
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

'''

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
replace_once(lobby_path, avatar_initials_end, avatar_initials_end + image_dialog)

old_select_image = '''  Future<void> _selectImage() async {
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
'''

new_select_image = '''  Future<void> _changeProfileImage() async {
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
'''
replace_once(lobby_path, old_select_image, new_select_image)

text = Path(lobby_path).read_text()
old_current_avatar = '''    final currentAvatarAsset = _selectedImage == null
        ? _selectedAvatarAsset ?? humanAvatarAssetFromPhotoUrl(profile.photoUrl)
        : null;

'''
if old_current_avatar not in text:
    raise SystemExit('Variável currentAvatarAsset não encontrada')
text = text.replace(old_current_avatar, '', 1)
text = text.replace("tooltip: 'Escolher nova foto',", "tooltip: 'Alterar imagem',", 1)
text = text.replace(
    '_saving || _selectingImage ? null : _selectImage,',
    '_saving || _selectingImage ? null : _changeProfileImage,',
    1,
)
text = text.replace(
    ": 'Clique na câmera ou escolha um avatar abaixo.',",
    ": 'Toque na câmera para alterar sua imagem.',",
    1,
)

avatar_section_start = text.index(
    "              const SizedBox(height: 16),\n"
    "              Align(\n"
    "                alignment: Alignment.centerLeft,\n"
    "                child: Text(\n"
    "                  'ESCOLHA UM AVATAR',"
)
avatar_section_end = text.index(
    "              const SizedBox(height: 20),\n"
    "              TextField(",
    avatar_section_start,
)
text = (
    text[:avatar_section_start]
    + text[avatar_section_end:]
)
Path(lobby_path).write_text(text)


test_path = 'test/widget_test.dart'
test = Path(test_path).read_text()

old_photo_first = '''    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.text('Nova foto selecionada.'), findsOneWidget);
'''
new_photo_first = '''    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialogo-trocar-imagem')), findsOneWidget);
    expect(find.byKey(const ValueKey('lista-avatares-perfil')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('escolher-camera-fotos')));
    await tester.pumpAndSettle();
    expect(find.text('Nova foto selecionada.'), findsOneWidget);
'''
if test.count(old_photo_first) != 2:
    raise SystemExit(f'Esperava 2 fluxos de foto, encontrei {test.count(old_photo_first)}')
test = test.replace(old_photo_first, new_photo_first, 2)

old_avatar_test = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final avatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
    await tester.ensureVisible(avatar);
    await tester.tap(avatar);
    await tester.pump();

    expect(find.text('Novo avatar selecionado.'), findsOneWidget);
    expect(authService.updateProfileCalls, 0);

    await tester.tap(find.byKey(const ValueKey('cancelar-perfil')));
    await tester.pumpAndSettle();
    expect(authService.savedAvatarAsset, isNull);
    expect(authService.currentUser?.photoUrl, isEmpty);

    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    final savedAvatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
    await tester.ensureVisible(savedAvatar);
    await tester.tap(savedAvatar);
    await tester.pump();
'''
new_avatar_test = '''    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
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
    await tester.ensureVisible(avatar);
    await tester.tap(avatar);
    await tester.pumpAndSettle();

    expect(find.text('Novo avatar selecionado.'), findsOneWidget);
    expect(authService.updateProfileCalls, 0);

    await tester.tap(find.byKey(const ValueKey('cancelar-perfil')));
    await tester.pumpAndSettle();
    expect(authService.savedAvatarAsset, isNull);
    expect(authService.currentUser?.photoUrl, isEmpty);

    await tester.tap(find.byKey(const ValueKey('abrir-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trocar-foto-perfil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('escolher-avatar')));
    await tester.pumpAndSettle();
    final savedAvatar = find.byKey(const ValueKey('escolher-avatar-perfil-8'));
    await tester.ensureVisible(savedAvatar);
    await tester.tap(savedAvatar);
    await tester.pumpAndSettle();
'''
if old_avatar_test not in test:
    raise SystemExit('Teste de avatar original não encontrado')
test = test.replace(old_avatar_test, new_avatar_test, 1)
Path(test_path).write_text(test)
