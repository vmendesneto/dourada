# Douradinha

Jogo de Douradinha em Flutter para seis participantes: um jogador humano e
cinco robôs, divididos em dois trios alternados.

## Jogar pela internet

Abra **[vmendesneto.github.io/dourada](https://vmendesneto.github.io/dourada/)**.
O GitHub Pages é atualizado automaticamente a cada envio para a branch `main`.

## O que já está implementado

- baralho de 40 cartas (sem 8, 9 e 10);
- nove manilhas fixas, do 7 de Ouros até a Dama de Ouros;
- distribuição de três cartas para cada participante e rodízio do pé;
- até três mãos por disputa, incluindo as regras de empate;
- primeira mão como desempate e disputa sem tentos quando as três mãos empatam;
- vencedor da mão abrindo a seguinte; em empate, permanece quem abriu a mão;
- placar até 12 tentos;
- valores falados de 2, 4 (Truco), 6, 9 e 12, marcando respectivamente
  1, 2, 3, 4 e 6 tentos reais, com aceite, aumento e desistência;
- aumentos alternados obrigatoriamente entre os trios;
- diálogo informando quando o trio adversário aceita o desafio ou corre;
- mão de dez, consulta às cartas do trio e desistência por um tento;
- robôs adversários que desafiam, aceitam, aumentam e blefam;
- decisão estatística e coletiva dos robôs: cada parceiro sinaliza se corre,
  aceita ou aumenta usando apenas a própria mão e as cartas já abertas, sem
  revelar suas cartas aos demais;
- limite de uma avaliação de desafio do trio por mão, com pedidos e aumentos
  probabilísticos; mãos fortes ajudam, mas não garantem truco, e blefes raros
  continuam possíveis;
- decisões de aposta do Trio Azul exclusivas do jogador humano; os parceiros
  robôs apenas jogam suas próprias cartas;
- relógio individual de 15 segundos, reduzido para 12 e depois 8 segundos após
  estouros, com escolha automática de carta para a partida nunca travar;
- interface responsiva em modo paisagem, consulta à ordem das manilhas e
  destaque animado da carta vencedora.

## Executar

```sh
flutter pub get
flutter run
```

## Verificar

```sh
flutter analyze
flutter test
```

O motor da partida está separado da interface em `lib/game/douradinha_game.dart`,
o que permite substituir os robôs por jogadores remotos na próxima etapa sem
duplicar as regras do jogo.
