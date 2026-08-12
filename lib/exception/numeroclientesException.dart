class NumeroClientesException implements Exception {
  final int numeroClientes;
  NumeroClientesException(this.numeroClientes);

  @override
  String toString() {
    return "Numero de Clientes deve ser igual a 2 ou 4!";
  }
}


