import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../Providers/jogadores_provider.dart';
import '../../deck/pontuacao.dart';

Widget numeros(
    Function(String) callback,
    WidgetRef ref,
    List<String> cartasJogador,
    int qualJogador,
    String mensagem,
    List<int> resultadosDasMaosT1, Color cor) {
  final state = ref.watch(jogadoresProvider);
  final data = ref.watch(jogadoresProvider.notifier);
  final rodada = ref.watch(rodadaProvider.notifier);
  final stateRodada = ref.watch(rodadaProvider);
  bool ehVezDoJogador() {
    switch (qualJogador) {
      case 1:
        return state.vezDoJogador6;
      case 2:
        return state.vezDoJogador1;
      case 3:
        return state.vezDoJogador2;
      case 4:
        return state.vezDoJogador3;
      case 5:
        return state.vezDoJogador4;
      case 6:
        return state.vezDoJogador5;
      default:
        return false;
    }
  }

  return Column(mainAxisSize: MainAxisSize.min, children: [
    Text(qualJogador.toString(),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cor)),
    Container(
        padding: const EdgeInsets.all(2),
        alignment: Alignment.center,
        color: Colors.blue,
        width: 270,
        height: 60,
        // Defina um altura fixa para o Container
        child: Row(children: [
          ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: cartasJogador.length,
            itemBuilder: (BuildContext context, int index) {
              String nomeImagemCarta =
                  "assets/images/cartas/${cartasJogador[index]}.png";
              return Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      //state.vezDoJogador6 = true;
                      await data.incluirCarta(
                          cartasJogador[index], qualJogador);
                      callback(mensagem);
                      if (qualJogador == 6) {
                        await Future.delayed(const Duration(seconds: 2));
                        await rodada.vencedorRodada(ref);
                        await data.resetJogador();
                        resultadosDasMaosT1.add(stateRodada.pontosTrio1);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        // Definindo a decoração
                        color: Colors.white, // Cor de fundo do container
                        border: Border.all(
                          color: ehVezDoJogador()
                              ? Colors.green
                              : Colors.grey, // Cor da borda
                          width: 2.0, // Largura da borda
                        ),
                        borderRadius: BorderRadius.circular(
                            4.0), // Arredondamento dos cantos da borda
                      ),
                      // Fundo branco para destacar a imagem (ajuste conforme necessário)
                      height: 50,
                      // Altura do container, ajuste conforme necessário
                      width: 50,
                      // Largura do container, ajuste conforme necessário
                      child: Image.asset(nomeImagemCarta,
                          fit: BoxFit.fill), // Exibindo a imagem da carta
                    ),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                ],
              );
            },
          ),
          ehVezDoJogador()
              ? ElevatedButton(
                  child: Text("Truco"),
                  onPressed: () {},
                )
              : Container(),
        ])),
  ]);
}
