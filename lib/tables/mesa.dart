import '../deck/baralho.dart';
import '../deck/carta.dart';
import 'jogadas.dart';

class Mesa {
  Baralho baralho;
  Carta? vira;
  Jogadas? jogadas;

  Mesa() : baralho = Baralho() {
    baralho.iniciar();
  }

  Mesa.withBaralho(this.baralho);

  Mesa.withAll(this.baralho, this.vira, this.jogadas);

  Baralho getBaralho() {
    return baralho;
  }

  void setBaralho(Baralho baralho) {
    this.baralho = baralho;
  }

  Carta getVira() {
    return vira!;
  }

  void setVira(Carta vira) {
    this.vira = vira;
  }

  Jogadas getJogadas() {
    return jogadas!;
  }

  void setJogadas(Jogadas jogadas) {
    this.jogadas = jogadas;
  }
}
