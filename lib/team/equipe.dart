import 'jogador.dart';

class Equipe {
  String? nome;
  int? partidasVencidas = 0;
  int? maosVencidas = 0;
  int? rodadasVencidas = 0;
  List<Jogador>? jogadores;
  static const int? MAX_JOGADORES = 3;

  Equipe(this.nome) : jogadores = [];

  factory Equipe.comJogador(String nome, Jogador jogador) {
    var equipe = Equipe(nome);
    equipe.inserirJogador(jogador);
    return equipe;
  }

  factory Equipe.comDoisJogadores(
      String nome, Jogador jogador1, Jogador jogador2) {
    var equipe = Equipe(nome);
    equipe.inserirJogador(jogador1);
    equipe.inserirJogador(jogador2);
    return equipe;
  }

  void setNome(String nome) {
    this.nome = nome;
  }

  void setPartidasVencidas(int partidasVencidas) {
    this.partidasVencidas = partidasVencidas;
  }

  void setMaosVencidas(int maosVencidas) {
    this.maosVencidas = maosVencidas;
  }

  void setRodadasVencidas(int rodadasVencidas) {
    this.rodadasVencidas = rodadasVencidas;
  }

  bool inserirJogador(Jogador jogador) {
    if (jogador != null && jogadores!.length < MAX_JOGADORES!) {
      jogadores!.add(jogador);
      return true;
    }
    return false;
  }

  bool removerJogadorPorIndice(int indice) {
    if (indice >= 0 && indice < jogadores!.length) {
      jogadores!.removeAt(indice);
      return true;
    }
    return false;
  }

  bool removerJogador(Jogador jogador) {
    return jogadores!.remove(jogador);
  }

  Jogador? obterJogador(int indice) {
    if (indice >= 0 && indice < jogadores!.length) {
      return jogadores![indice];
    }
    return null;
  }

  bool possuiJogador(Jogador jogador) {
    return jogadores!.contains(jogador);
  }

  bool possuiVaga() {
    return jogadores!.length < MAX_JOGADORES!;
  }

  bool estaVazia() {
    return jogadores!.isEmpty;
  }

  int qtdJogadores() {
    return jogadores!.length;
  }
}
