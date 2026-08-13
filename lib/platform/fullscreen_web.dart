import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> enterGameFullscreen() async {
  if (web.document.fullscreenElement != null) return true;
  final element = web.document.documentElement;
  if (element == null) return false;

  try {
    await element
        .requestFullscreen(web.FullscreenOptions(navigationUI: 'hide'))
        .toDart;
    return web.document.fullscreenElement != null;
  } on Object {
    return false;
  }
}

Future<void> exitGameFullscreen() async {
  if (web.document.fullscreenElement == null) return;
  try {
    await web.document.exitFullscreen().toDart;
  } on Object {
    // O navegador também permite sair com Esc; não há ação adicional necessária.
  }
}
