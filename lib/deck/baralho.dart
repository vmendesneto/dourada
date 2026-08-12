import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'carta.dart';

/// Modelo legado mantido para as classes de servidor ainda presentes no projeto.
class Baralho {
  final List<Carta> cartas = [];

  void iniciar() {
    cartas
      ..clear()
      ..addAll([
        for (var tipo = 0; tipo < Carta.TIPO_NOMES.length; tipo++)
          for (var naipe = 0; naipe < Carta.NAIPE_NOMES.length; naipe++)
            Carta(tipo, naipe),
      ]);
  }
}

class BaralhoState {
  List<String> baralho;

  BaralhoState({this.baralho = const []});
}

class BaralhoController extends StateNotifier<BaralhoState> {
  BaralhoController([BaralhoState? state]) : super(BaralhoState());
  Random random = Random();

  List<String> embaralhar() {
    List<String> baralhoNovo = [];
    List<String> TIPO_NOMES = [
      "4",
      "5",
      "6",
      "7",
      "Q",
      "J",
      "K",
      "A",
      "2",
      "3"
    ];
    List<String> NAIPE_NOMES = ["o", "e", "c", "p"];
    for (int i = 0; i < TIPO_NOMES.length; i++) {
      for (int j = 0; j < NAIPE_NOMES.length; j++) {
        baralhoNovo.add(TIPO_NOMES[i] + NAIPE_NOMES[j]);
      }
    }
    List<String> listaEmbaralhada = List<String>.from(baralhoNovo)
      ..shuffle(random);
    state = BaralhoState(baralho: listaEmbaralhada);
    return listaEmbaralhada;
  }
}
