
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../deck/jogadores.dart';

final jogadoresProvider = StateNotifierProvider<JogadoresController, JogadoresState>(
        (ref) {
      return JogadoresController();
    }
);
