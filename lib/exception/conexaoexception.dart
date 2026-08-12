class ConexaoException implements Exception {
  @override
  String toString() {
    return "nao foi possivel se conectar a nenhum dos enderecos do arquivo .txt de enderecos ip!";
  }
}


