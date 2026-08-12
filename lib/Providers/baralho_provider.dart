import 'package:dourada/deck/baralho.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final baralhoProvider = StateNotifierProvider<BaralhoController, BaralhoState>(
      (ref) {
        return BaralhoController();
      }
);

