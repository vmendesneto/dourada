import 'package:dourada/deck/baralho.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JogadoresState {
  List<String> jogador1;
  List<String> jogador2;
  List<String> jogador3;
  List<String> jogador4;
  List<String> jogador5;
  List<String> jogador6;

  bool vezDoJogador1;
  bool vezDoJogador2;
  bool vezDoJogador3;
  bool vezDoJogador4;
  bool vezDoJogador5;
  bool vezDoJogador6;

  List<String>? trio1;
  List<String>? trio2;

  List<String>? sequencia;

  JogadoresState(
      {this.jogador1 = const [],
      this.jogador2 = const [],
      this.jogador3 = const [],
      this.jogador4 = const [],
      this.jogador5 = const [],
      this.jogador6 = const [],
      this.vezDoJogador1 = false,
      this.vezDoJogador2 = false,
      this.vezDoJogador3 = false,
      this.vezDoJogador4 = false,
      this.vezDoJogador5 = false,
      this.vezDoJogador6 = true,
      this.trio1,
      this.trio2,
      this.sequencia});
}

class JogadoresController extends StateNotifier<JogadoresState> {
  JogadoresController([JogadoresState? state]) : super(JogadoresState());

  receberCarta() {
    final baralho = BaralhoController().embaralhar();
    List<String> jogador1a = [];
    List<String> jogador2a = [];
    List<String> jogador3a = [];
    List<String> jogador4a = [];
    List<String> jogador5a = [];
    List<String> jogador6a = [];
    jogador1a = baralho.take(3).toList();
    jogador2a = baralho.sublist(4, 7).toList();
    jogador3a = baralho.sublist(8, 11).toList();
    jogador4a = baralho.sublist(12, 15).toList();
    jogador5a = baralho.sublist(16, 19).toList();
    jogador6a = baralho.sublist(20, 23).toList();
    state = JogadoresState(
        jogador1: jogador1a,
        jogador2: jogador2a,
        jogador3: jogador3a,
        jogador4: jogador4a,
        jogador5: jogador5a,
        jogador6: jogador6a,
        trio1: state.trio1,
        trio2: state.trio2,
        sequencia: state.sequencia,
        vezDoJogador1: state.vezDoJogador1,
        vezDoJogador2: state.vezDoJogador2,
        vezDoJogador3: state.vezDoJogador3,
        vezDoJogador4: state.vezDoJogador4,
        vezDoJogador5: state.vezDoJogador5,
        vezDoJogador6: state.vezDoJogador6);
  }

  //INCLUINDO A CARTA DE CADA JOGADOR NO SEU RESPECTIVO TRIO
  incluirCarta(String numero, int jogador) {
    //INCLUINDO A CARTA nO TRIO CORRESPONDENTE
    List<String>? trio1 = [];
    List<String>? trio2 = [];
    List<String>? sequenciaCartas = state.sequencia ?? [];
    if (state.trio1 == null) {
      trio1 = [];
    } else {
      trio1 = state.trio1;
    }
    if (state.trio2 == null) {
      trio2 = [];
    } else {
      trio2 = state.trio2;
    }
    bool vezDoJog1 = false;
    bool vezDoJog2 = false;
    bool vezDoJog3 = false;
    bool vezDoJog4 = false;
    bool vezDoJog5 = false;
    bool vezDoJog6 = false;
    switch (jogador) {
      case 1:
        vezDoJog1 = true;
        break;
      case 2:
        vezDoJog2 = true;
        break;
      case 3:
        vezDoJog3 = true;
        break;
      case 4:
        vezDoJog4 = true;
        break;
      case 5:
        vezDoJog5 = true;
        break;
      case 6:
        vezDoJog6 = true;
        break;
      default:
      // Caso não seja nenhum dos casos acima, você pode decidir como lidar.
      // Por exemplo, não fazer nada ou lançar um erro.
        print("Número de jogador inválido: $jogador");
    }

    List<String> jogador1a = state.jogador1;
    List<String> jogador2a = state.jogador2;
    List<String> jogador3a = state.jogador3;
    List<String> jogador4a = state.jogador4;
    List<String> jogador5a = state.jogador5;
    List<String> jogador6a = state.jogador6;
    if (vezDoJog1 || vezDoJog3 || vezDoJog5) {
      trio1!.add(numero);
      sequenciaCartas.add(numero);
      if (vezDoJog1) {
        jogador1a.remove(numero);
      }
      if (vezDoJog3) {
        jogador3a.remove(numero);
      }
      if (vezDoJog5) {
        jogador5a.remove(numero);
      }
    } else {
      trio2!.add(numero);
      sequenciaCartas.add(numero);
      if (vezDoJog2) {
        jogador2a.remove(numero);
      }
      if (vezDoJog4) {
        jogador4a.remove(numero);
      }
      if (vezDoJog6) {
        jogador6a.remove(numero);
      }
    }
    state = JogadoresState(
        trio1: trio1,
        trio2: trio2,
        jogador1: jogador1a,
        jogador6: jogador6a,
        jogador5: jogador5a,
        jogador4: jogador4a,
        jogador3: jogador3a,
        jogador2: jogador2a,
        vezDoJogador1: vezDoJog1,
        vezDoJogador2: vezDoJog2,
        vezDoJogador3: vezDoJog3,
        vezDoJogador4: vezDoJog4,
        vezDoJogador5: vezDoJog5,
        vezDoJogador6: vezDoJog6,
    sequencia: sequenciaCartas);
  }

  resetJogador() {
    bool vezDoJog1 = false;
    bool vezDoJog2 = false;
    bool vezDoJog3 = false;
    bool vezDoJog4 = false;
    bool vezDoJog5 = false;
    bool vezDoJog6 = true;
    List<String> a = [];
    List<String>b = [];
    List<String> c = [];
    state = JogadoresState(
      vezDoJogador1: vezDoJog1,
        vezDoJogador2: vezDoJog2,
        vezDoJogador3: vezDoJog3,
        vezDoJogador4: vezDoJog4,
        vezDoJogador5: vezDoJog5,
        vezDoJogador6: vezDoJog6,
        trio1: a,
        trio2: b,
        sequencia: c,
        jogador1: state.jogador1,
        jogador6: state.jogador6,
        jogador5: state.jogador5,
        jogador4: state.jogador4,
        jogador3: state.jogador3,
        jogador2: state.jogador2,
    );
  }
}
