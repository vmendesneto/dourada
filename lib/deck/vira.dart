 // Assuming Carta is defined in another file

import 'carta.dart';

class Vira extends Carta {
  Vira(int tipo, int naipe) : super(tipo, naipe);
  Vira.escondida(int tipo, int naipe, bool escondida) : super.escondida(tipo, naipe, escondida);

  int obterManilha() {
    return (this.getTipo() + 1) % 10;
  }
}


