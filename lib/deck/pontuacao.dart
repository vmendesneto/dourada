import 'package:dourada/deck/regras.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Providers/jogadores_provider.dart';

final rodadaProvider =
    StateNotifierProvider<RodadaController, RodadaState>((ref) {
  return RodadaController();
});

class RodadaState {
  int pontosTrio1;
  int pontosTrio2;
  String venceu;
  int mao;
  int primeira;
  bool jogoTerminou;
  String mensagem;
  int tentos1;
  int tentos2;
  bool fimPartida;
  int aposta;

  RodadaState(
      {this.pontosTrio1 = 0,
      this.pontosTrio2 = 0,
      this.venceu = '',
      this.jogoTerminou = false,
      this.primeira = 0,
      this.mao = 0,
      this.mensagem = 'Vez do Jogador 1',
      this.tentos1 = 0,
      this.tentos2 = 0,
      this.fimPartida = false,
      this.aposta =2});
}

class RodadaController extends StateNotifier<RodadaState> {
  RodadaController([RodadaState? state]) : super(RodadaState());

  vencedorRodada(WidgetRef ref) {
    final stateJogad = ref.watch(jogadoresProvider);
    final dataJog = ref.watch(jogadoresProvider.notifier);

    List<String>? trio1 = stateJogad.trio1;
    List<String>? trio2 = stateJogad.trio2;
    List<String>? sequenciaCartas = stateJogad.sequencia;
    //TENHO DOURADA E VC NÃO JOGADOR 1 GANHA
    final regra = RegrasState();

    int ptsTrio1 = state.pontosTrio1;
    int ptsTrio2 = state.pontosTrio2;
    int maos = state.mao;
    int primeiras = state.primeira;
    String vencedor = state.venceu;
    bool jogAcabou = state.jogoTerminou;
    bool fimPart = state.fimPartida;
    String msg = state.mensagem;
    //CONTANDO OS TENTOS
    int tento1 = state.tentos1;
    int tento2 = state.tentos2;

    //COMEÇA COM 2 TENTOS SUBINDO CONFORME APOSTA
     int valendo = state.aposta;

    //REGRA DE QUEM GANHA
    List<String> douradas = regra.douradas!;
    List<String> manilhas = regra.manilhas!;
    List<String> cartas = regra.cartas!;

    if (trio1!.any((elemento) => douradas.contains(elemento)) &&
        !trio2!.any((elemento) => douradas.contains(elemento))) {
      ptsTrio1++;
      //NÃO TENHO DOURADA E VC TEM JOGADOR 2 GANHA
    } else if (!trio1.any((elemento) => douradas.contains(elemento)) &&
        trio2!.any((elemento) => douradas.contains(elemento))) {
      ptsTrio2++;
      //OS DOIS TEM DOURADA
    } else if (trio1.any((elemento) => douradas.contains(elemento)) &&
        trio2!.any((elemento) => douradas.contains(elemento))) {
      for (var i = douradas.length - 1; i >= 0; i--) {
        String letraAtual = douradas[i];
        // Verificar se a letra atual está em a ou b
        if (trio1.contains(letraAtual)) {
          ptsTrio1++;
          break; // Parar o loop se encontrar
        } else if (trio2.contains(letraAtual)) {
          ptsTrio2++;
          break; // Parar o loop se encontrar
        }
      }
      //TENHO MANILHA E VC NÃO JOGADOR 1 GANHA
    } else if (trio1.any((elemento) => manilhas.contains(elemento)) &&
        !trio2!.any((elemento) => manilhas.contains(elemento))) {
      ptsTrio1++;
      //NÃO TENHO MANILHA E VC TEM JOGADOR 2 GANHA
    } else if (!trio1.any((elemento) => manilhas.contains(elemento)) &&
        trio2!.any((elemento) => manilhas.contains(elemento))) {
      ptsTrio2++;
    }
    //OS DOIS TEM MANILHAS
    else if (trio1.any((elemento) => manilhas.contains(elemento)) &&
        trio2!.any((elemento) => manilhas.contains(elemento))) {
      for (var i = manilhas.length - 1; i >= 0; i--) {
        String letraAtual = manilhas[i];
        // Verificar se a letra atual está em a ou b
        if (trio1.contains(letraAtual)) {
          ptsTrio1++;
          break; // Parar o loop se encontrar
        } else if (trio2.contains(letraAtual)) {
          ptsTrio2++;
          break; // Parar o loop se encontrar
        }
      }
      //NÃO TEMOS NADA DE BOM, QUEM TEM CARTA MAIOR
    } else {
      int indiceMaiorTrio1 = -1;
      int indiceMaiorTrio2 = -1;
      // Encontrar o índice mais alto das cartas de cada trio na lista cartas
      for (String carta in trio1) {
        int indice = cartas.indexOf(carta[0]);
        print('indice1 $indice');
        if (indice > indiceMaiorTrio1) {
          indiceMaiorTrio1 = indice;
        }
      }
      for (String carta in trio2!) {
        int indice = cartas.indexOf(carta[0]);
        print('indice2 $indice');
        if (indice > indiceMaiorTrio2) {
          indiceMaiorTrio2 = indice;
        }
      }

// Comparar os índices mais altos encontrados para cada trio
      if (indiceMaiorTrio1 > indiceMaiorTrio2) {
        ptsTrio1++;
      } else if (indiceMaiorTrio2 > indiceMaiorTrio1) {
        ptsTrio2++;
      } else {
        // Se os índices mais altos são iguais, então é empate
        print("Empate");
        maos++;
      }
    }
    maos++;


    //ZERAR AS CARTAS DO TRIO PARA NOVA RODADA
    trio1 = [];
    trio2 = [];
    if (ptsTrio1 == 2 || ptsTrio2 == 2) {
      maos = 3;
    }
    print('rodadas $maos');
    if (maos == 1) {
      if (ptsTrio1 > 0) {
        primeiras = 1;
      } else {
        primeiras = 2;
      }
    }

    if (maos == 3 || maos == 4) {
      jogAcabou = true;
      if (ptsTrio1 > ptsTrio2) {
        vencedor = "O Trio 1 venceu";
      } else if (ptsTrio1 == ptsTrio2) {
        if (primeiras == 1) {
          vencedor = "O Trio 1 venceu";
        } else {
          vencedor = "O Trio 2 venceu";
        }
      } else {
        vencedor = "O Trio 2 venceu";
      }
    }
    //CONDIÇÃO PARA CASO EMPATE AS 3 RODADAS
    if (maos == 6) {
      jogAcabou = true;
      if (ptsTrio1 > ptsTrio2) {
        vencedor = "O Trio 1 venceu";
      } else if (ptsTrio1 == ptsTrio2) {
        vencedor = "Empate";
      } else {
        vencedor = "O Trio 2 venceu";
      }
    }
    //DISTRIBUINDO OS TENTOS PARA O VENCEDOR
      if (jogAcabou) {
        if (ptsTrio1 > ptsTrio2) {
          tento1 = tento1 + valendo;
        } else if (ptsTrio1 == ptsTrio2) {} else {
          tento2 = tento2 + valendo;
        }
        if (tento2 >= 12 || tento1 >= 12) {
          fimPart = true;
          if (ptsTrio1 > ptsTrio2) {
            vencedor = "O Trio 1 venceu";
          } else if (ptsTrio1 == ptsTrio2) {
            vencedor = "Empate";
          } else {
            vencedor = "O Trio 2 venceu";
          }
        } else {
          resetMao();
          dataJog.resetJogador();
          dataJog.receberCarta();
          ptsTrio1 = 0;
          ptsTrio2 = 0;
          trio1 = [];
          trio2 = [];
          maos = 0;
          primeiras = 0;
          vencedor = "";
          jogAcabou = false;
          fimPart = false;
          msg = "Vez do Jogador 1";
          valendo = 2;
          state = RodadaState(
            mensagem: msg,
            pontosTrio1: ptsTrio1,
            pontosTrio2: ptsTrio2,
            jogoTerminou: jogAcabou,
            primeira: primeiras,
            mao: maos,
            venceu: vencedor,
            tentos1: tento1,
            tentos2: tento2,
            fimPartida: fimPart,
            aposta: valendo,
          );
        }
      }
    print('pontos trio 1 $ptsTrio1');
    print('pontos trio 2 $ptsTrio2');
    print('pontos tento 1 $tento1');
    print('pontos tento 2 $tento2');

    state = RodadaState(
        pontosTrio1: ptsTrio1,
        pontosTrio2: ptsTrio2,
        mensagem: msg,
        jogoTerminou: jogAcabou,
        primeira: primeiras,
        mao: maos,
        venceu: vencedor,
        tentos1: tento1,
        tentos2: tento2,
        fimPartida: fimPart,
    aposta: valendo);
  }

  void reset() {
    // Redefinir o estado para os valores iniciais
    state = RodadaState(
      pontosTrio1: 0,
      pontosTrio2: 0,
      venceu: '',
      mao: 0,
      primeira: 0,
      jogoTerminou: false,
      mensagem: 'Vez do Jogador 1',
      tentos1: state.tentos1,
      tentos2: state.tentos2,
      fimPartida: state.fimPartida,
      aposta: state.aposta,
    );
  }

  void resetMsg() {
    // Redefinir o estado para os valores iniciais
    state = RodadaState(
      mensagem: 'Vez do Jogador 1',
      pontosTrio1: state.pontosTrio1,
      pontosTrio2: state.pontosTrio2,
      jogoTerminou: state.jogoTerminou,
      primeira: state.primeira,
      mao: state.mao,
      venceu: state.venceu,
      tentos1: state.tentos1,
      tentos2: state.tentos2,
      fimPartida: state.fimPartida,
      aposta: state.aposta,
    );
  }

  resetMao() {
    List<String>? trio1 = [];
    List<String>? trio2 = [];
    int ptsTrio1 = 0;
    int ptsTrio2 = 0;
    int maos = 0;
    int primeiras = 0;
    String vencedor = "";
    bool jogAcabou = false;
    bool fimPart = false;
    String msg = "Vez do Jogador 1";
    //CONTANDO OS TENTOS
    int tento1 = state.tentos1;
    int tento2 = state.tentos2;
    int valendo = 2;
    state = RodadaState(
      mensagem: msg,
      pontosTrio1: ptsTrio1,
      pontosTrio2: ptsTrio2,
      jogoTerminou: jogAcabou,
      primeira: primeiras,
      mao: maos,
      venceu: vencedor,
      tentos1: tento1,
      tentos2: tento2,
      fimPartida: fimPart,
      aposta: valendo,
    );
  }
}
