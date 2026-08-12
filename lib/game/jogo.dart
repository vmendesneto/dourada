import 'package:dourada/game/status.dart';

import '../deck/baralho.dart';

import '../tables/mesa.dart';

import '../team/equipe.dart';
import '../team/jogador.dart';



class Jogo {
  Status? status;
  Mesa? mesa;
  Equipe? equipe1;
  Equipe? equipe2;
  List<Jogador>? jogadores;
  List<Baralho>? cartasJogadores;

  Jogo(String nomeEquipe1, String nomeEquipe2) {
    this.status = Status();
    this.mesa = Mesa();
    this.equipe1 = Equipe(nomeEquipe1);
    this.equipe2 = Equipe(nomeEquipe2);
    this.jogadores = [];
    this.cartasJogadores = [];
  }

  Jogo.full(this.status, this.mesa, this.equipe1, this.equipe2, this.jogadores, this.cartasJogadores);

  bool inserirParticipante(Jogador jogador) {
    Equipe equipeEscolhida;
    bool inseriu = false;
    if (this.equipe1!.possuiVaga() || this.equipe2!.possuiVaga()) {
      if (this.equipe1!.qtdJogadores() <= this.equipe2!.qtdJogadores()) {
        equipeEscolhida = this.equipe1!;
      } else {
        equipeEscolhida = this.equipe2!;
      }
      this.jogadores!.add(jogador);
      this.cartasJogadores!.add(Baralho());
      equipeEscolhida.inserirJogador(jogador);
      inseriu = true;
    }
    return inseriu;
  }

  bool inserirParticipanteComEquipe(Jogador jogador, Equipe equipe) {
    return inserirParticipanteComCartas(jogador, Baralho(), equipe);
  }

  bool inserirParticipanteComCartas(Jogador jogador, Baralho cartasJogador, Equipe equipe) {
    bool inseriu = false;
    if (equipe.possuiVaga()) {
      this.jogadores!.add(jogador);
      this.cartasJogadores!.add(cartasJogador);
      equipe.inserirJogador(jogador);
      inseriu = true;
    }
    return inseriu;
  }

  bool removerParticipante(Jogador jogador) {
    bool removeu = true;
    if (this.equipe1!.possuiJogador(jogador)) {
      this.equipe1!.removerJogador(jogador);
    } else if (this.equipe2!.possuiJogador(jogador)) {
      this.equipe2!.removerJogador(jogador);
    } else {
      removeu = false;
    }
    return removeu;
  }

  Jogador obterJogador(int indice) {
    return this.jogadores![indice];
  }

  Baralho obterCartasJogador(int indice) {
    return this.cartasJogadores![indice];
  }

  bool existeJogador(Jogador jogador) {
    return this.jogadores!.contains(jogador);
  }
}


