import 'dart:io';
import 'dart:async';

class ServidorTruco {
  final int porta = 8080;
  ServerSocket? _serverSocket;
  bool _parado = true;
  bool _pausado = false;

  // A lista de conexões cliente pode ser gerenciada como uma lista de Sockets.
  List<Socket> _conexoesCliente = [];

  ServidorTruco() {
    _iniciarServidor();
  }

  void _iniciarServidor() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, porta);
    print('Servidor iniciado na porta $porta');
    _serverSocket?.listen(_gerenciarConexao,
        onError: _erroServidor,
        onDone: _fecharServidor);
  }

  void _gerenciarConexao(Socket cliente) {
    print('Cliente conectado: ${cliente.remoteAddress.address}:${cliente.remotePort}');
    _conexoesCliente.add(cliente);
    // Aqui você pode escutar as mensagens do cliente ou enviar mensagens.
  }

  void pausar() {
    _pausado = true;
    print('Servidor pausado.');
  }

  void continuar() {
    _pausado = false;
    print('Servidor continuado.');
  }

  void parar() {
    _parado = true;
    _serverSocket?.close();
    print('Servidor parado.');
  }

  void _erroServidor(e) {
    print('Erro no servidor: $e');
  }

  void _fecharServidor() {
    print('Servidor fechado.');
  }

// Métodos adicionais para gerenciar clientes, enviar e receber mensagens podem ser adicionados aqui.
}


