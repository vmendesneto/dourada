class Carta {
  static const List<String> TIPO_NOMES = ["4", "5", "6", "7", "Rainha", "Valete", "Rei", "Ás", "2", "3"];
  static const List<String> NAIPE_NOMES = ["Ouro", "Espadilha", "Copas", "Paus"];
  int tipo;
  int naipe;
  bool escondida = false;

  Carta(this.tipo, this.naipe);
  Carta.escondida(this.tipo, this.naipe, this.escondida);

  int getTipo() => tipo;
  void setTipo(int tipo) {
    this.tipo = tipo;
  }

  int getNaipe() => naipe;
  void setNaipe(int naipe) {
    this.naipe = naipe;
  }

  bool isEscondida() => escondida;
  void setEscondida(bool escondida) {
    this.escondida = escondida;
  }

  String getTipoNome() {
    return TIPO_NOMES[this.tipo];
  }

  String getNaipeNome() {
    return NAIPE_NOMES[this.naipe];
  }

  static bool tipoValido(int tipo) {
    return ((tipo >= 0) && (tipo < TIPO_NOMES.length));
  }

  static bool naipeValido(int naipe) {
    return ((naipe >= 0) && (naipe < NAIPE_NOMES.length));
  }
}


