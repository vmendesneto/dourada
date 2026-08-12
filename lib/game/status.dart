
import '../team/equipe.dart';

class Status {
  int partidaAtual = 1;
  int maoAtual = 1;
  int rodadaAtual = 1;
  Equipe? vencedorPrimeiraRodada;
  int valorMao = 1;

  Status();

  Status.custom(this.partidaAtual, this.maoAtual, this.rodadaAtual,
      this.vencedorPrimeiraRodada, this.valorMao);

  int getPartidaAtual() => partidaAtual;

  setPartidaAtual(int partidaAtual) => this.partidaAtual = partidaAtual;

  int getMaoAtual() => maoAtual;

  setMaoAtual(int maoAtual) => this.maoAtual = maoAtual;

  int getRodadaAtual() => rodadaAtual;

  setRodadaAtual(int rodadaAtual) => this.rodadaAtual = rodadaAtual;

  Equipe? getVencedorPrimeiraRodada() => vencedorPrimeiraRodada;

  setVencedorPrimeiraRodada(Equipe? vencedorPrimeiraRodada) =>
      this.vencedorPrimeiraRodada = vencedorPrimeiraRodada;

  int getValorMao() => valorMao;

  setValorMao(int valorMao) => this.valorMao = valorMao;

  static bool partidaAtualValida(int partidaAtual) =>
      partidaAtual >= 1 && partidaAtual <= 3;

  static bool maoAtualValida(int maoAtual) => maoAtual >= 1 && maoAtual <= 12;

  static bool rodadaAtualValida(int rodadaAtual) =>
      rodadaAtual >= 1 && rodadaAtual <= 3;

  bool incrementarRodadaAtual() {
    bool ok = true;
    int novaRodada = this.rodadaAtual + 1;
    if (rodadaAtualValida(novaRodada)) {
      this.rodadaAtual = novaRodada;
    } else {
      this.rodadaAtual = novaRodada % 3;
      int novaMao = this.maoAtual + 1;
      if (maoAtualValida(novaMao)) {
        this.maoAtual = novaMao;
      } else {
        this.maoAtual = novaMao % 12;
        int novaPartida = this.partidaAtual + 1;
        if (partidaAtualValida(novaPartida)) {
          this.partidaAtual = novaPartida;
        } else {
          this.rodadaAtual = 3;
          this.maoAtual = 12;
          ok = false;
        }
      }
    }
    return ok;
  }

  static bool valorMaoValida(int valorMao) =>
      valorMao == 1 || valorMao == 3 || valorMao == 6 || valorMao == 9 || valorMao == 12;

  bool incrementarValorMao() {
    int incremento;
    bool ok = false;
    if (this.valorMao == 1)
      incremento = 2;
    else
      incremento = 3;
    if (this.valorMao != 12) {
      this.valorMao += incremento;
      ok = true;
    }
    return ok;
  }
}


