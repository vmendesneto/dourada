import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OperarioServidor {
  final Socket conexaoCliente;

  OperarioServidor(this.conexaoCliente);

  void executar() async {
    // Transforma o stream de bytes para um stream de strings.
    Stream<String> lines = conexaoCliente
        .transform(utf8.decoder as StreamTransformer<Uint8List, dynamic>) // Decodifica os bytes para UTF-8.
        .transform(const LineSplitter()); // Divide o stream em linhas.

    await for (String line in lines) {
      print('Dados recebidos: $line');
      if (line == 'stop') {
        await conexaoCliente.close();
        break;
      } else {
        conexaoCliente.write('recebido\n');
      }
    }

    print('Conexão fechada pelo cliente ou servidor.');
  }
}
