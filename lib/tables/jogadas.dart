import 'dart:collection';

import '../deck/carta.dart';


class Jogadas {
  Map<String, Carta> jogadas = HashMap<String, Carta>(); // Inicialização correta

  void inserir(String nome, Carta carta) {
    jogadas[nome] = carta;
  }

  void remover(String nome) {
    jogadas.remove(nome);
  }

  Carta? obter(String nome) {
    return jogadas[nome];
  }

  bool existe(String nome) {
    return jogadas.containsKey(nome);
  }
}
