# Terminologia da Douradinha

Use sempre estes termos nas mensagens da interface, documentação, testes e novas
regras de negócio:

- **Mão**: rodada em que são jogadas as seis cartas, uma por jogador.
- **Partida**: conjunto de até três mãos necessário para definir quem ganha os
  pontos daquela disputa.
- **Queda**: conjunto de partidas que termina quando um trio alcança 12 pontos.

## Mapeamento do código legado

Alguns nomes internos atuais são anteriores a essa definição. Ao interpretar ou
alterar o código, considere:

- `trick`, `awaitingNextTrick`, `trickWinners` e `displayedHandNumber`
  representam uma **mão**;
- `hand`, `handFinished`, `handValue`, `_dealHand` e `startNextHand`
  representam uma **partida**;
- `match`, `matchWinner` e `gameOver` representam a **queda**.

Não replique a nomenclatura legada em novos textos apresentados ao jogador.
