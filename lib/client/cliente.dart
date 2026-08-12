import 'dart:io';

class Cliente {
  Socket? socket;

  Cliente(List<String> enderecosHost, int porta) {
    this.socket = definirHost(enderecosHost, porta);
    if (this.socket == null) throw Exception("ConexaoException");
  }

  Socket? definirHost(List<String> enderecosHost, int porta) {
    Socket? possivelSocket;
    int indice = 0;
    bool encontrou = false;
    while (!encontrou && indice < enderecosHost.length) {
      try {
        possivelSocket = Socket.connect(enderecosHost[indice], porta) as Socket?;
        encontrou = true;
      } on SocketException catch (e) {
        // Connection exception
      } on Exception catch (e) {
        // Unknown host or other IO exceptions
      } finally {
        indice++;
      }
    }
    return possivelSocket;
  }

  void executar() async {
    try {
      var dout = this.socket!.addStream;
      var din = this.socket!.listen;
      print("escrever para o servidor: ");
      String request = stdin.readLineSync() ?? "";
      while (request != "stop") {
        this.socket!.write(request);
        await this.socket!.flush();
        // Listening to the response
        this.socket!.listen((List<int> event) {
          final answer = String.fromCharCodes(event);
          print(answer);
        });
        print("escrever para o servidor: ");
        request = stdin.readLineSync() ?? "";
      }
      this.socket!.close();
    } on SocketException catch (e) {
      print("Conexao com o servidor foi recusada!");
    } on IOException catch (e) {
      print("Ocorreu uma IOException do lado cliente!");
    } catch (e) {
      print("Ocorreu uma Exception do lado cliente!");
    }
  }

  static void main(List<String> args) {
    try {
      // Assuming SimpleFile is a class you've defined to handle file operations in Dart
      // Dart has its own file handling classes such as File from dart:io
      // Here's a simple example of reading lines from a file
      var f = File('servidor-sockets.txt');
      List<String> lines = f.readAsLinesSync();
      Cliente cliente = Cliente(lines, 8080);
      cliente.executar();
    } catch (e) {
      print(e);
    }
  }
}

