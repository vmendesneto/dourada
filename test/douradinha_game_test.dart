import 'dart:math';

import 'package:dourada/game/douradinha_game.dart';
import 'package:dourada/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('baralho e hierarquia', () {
    test('usa exatamente as 40 cartas permitidas', () {
      final deck = PlayingCard.fullDeck();

      expect(deck, hasLength(40));
      expect(deck.map((card) => card.code).toSet(), hasLength(40));
      expect(deck.any((card) => ['8', '9', '10'].contains(card.rank)), isFalse);
    });

    test('ordena as nove manilhas fixas e as cartas simples', () {
      const ordered = [
        PlayingCard('Q', 'o'),
        PlayingCard('J', 'p'),
        PlayingCard('2', 'p'),
        PlayingCard('A', 'p'),
        PlayingCard('5', 'p'),
        PlayingCard('4', 'p'),
        PlayingCard('7', 'c'),
        PlayingCard('A', 'e'),
        PlayingCard('7', 'o'),
        PlayingCard('3', 'c'),
        PlayingCard('2', 'c'),
        PlayingCard('A', 'c'),
        PlayingCard('K', 'c'),
        PlayingCard('J', 'c'),
        PlayingCard('Q', 'c'),
        PlayingCard('7', 'e'),
        PlayingCard('6', 'c'),
        PlayingCard('5', 'c'),
        PlayingCard('4', 'c'),
      ];

      for (var index = 0; index < ordered.length - 1; index++) {
        expect(
            ordered[index].strength, greaterThan(ordered[index + 1].strength));
      }
    });

    test('usa somente os sete apelidos informados para as manilhas', () {
      const nicknames = {
        'Ae': 'Espadilha',
        '4p': 'Zap',
        '5p': 'Cinquinho',
        'Ap': 'Azinho',
        '2p': 'Dunguinha',
        'Jp': 'Valetinho',
        'Qo': 'Douradinha',
      };

      for (final card in PlayingCard.fullDeck()) {
        expect(card.nickname, nicknames[card.code]);
      }
      expect(
        const PlayingCard('A', 'e').displayName,
        'Ás de Espadas (Espadilha)',
      );
      expect(const PlayingCard('7', 'o').displayName, '7 de Ouros');
      expect(const PlayingCard('7', 'c').displayName, '7 de Copas');
    });
  });

  group('partida', () {
    test('mantém o resultado da mão visível por cinco segundos', () {
      expect(
        DouradinhaGame.handResultDisplayDuration,
        const Duration(seconds: 5),
      );
    });

    test('mostra somente a primeira, segunda ou terceira mão atual', () {
      final game = DouradinhaGame(random: Random(11));
      var safety = 0;

      while (!game.awaitingNextTrick &&
          game.phase == MatchPhase.playing &&
          safety++ < 100) {
        if (game.humanMustAnswerChallenge) {
          game.acceptHumanChallenge();
        } else if (game.pendingChallenge != null) {
          game.resolveBotChallenge();
        } else if (game.isHumanTurn) {
          game.playHumanCard(game.players[0].hand.first);
        } else {
          game.takeBotTurn();
        }
      }

      expect(game.awaitingNextTrick, isTrue);
      expect(game.lastCompletedHandNumber, 1);
      expect(game.displayedHandNumber, 1);

      game.beginNextTrick();
      expect(game.displayedHandNumber, 2);
    });

    test('cria um humano, cinco robôs e dois trios alternados', () {
      final game = DouradinhaGame(random: Random(7));

      expect(game.players, hasLength(6));
      expect(game.players.where((player) => player.isHuman), hasLength(1));
      expect(game.players.map((player) => player.team), [0, 1, 0, 1, 0, 1]);
      expect(game.players.every((player) => player.hand.length == 3), isTrue);
    });

    test('empate da mão exige força máxima nos dois trios', () {
      final game = DouradinhaGame(random: Random(3));
      final tied = [
        const PlayedCard(playerIndex: 0, card: PlayingCard('3', 'c')),
        const PlayedCard(playerIndex: 1, card: PlayingCard('3', 'o')),
      ];
      final sameTeam = [
        const PlayedCard(playerIndex: 0, card: PlayingCard('3', 'c')),
        const PlayedCard(playerIndex: 2, card: PlayingCard('3', 'o')),
        const PlayedCard(playerIndex: 1, card: PlayingCard('2', 'c')),
      ];

      expect(DouradinhaGame.resolveTrickWinner(tied, game.players), isNull);
      expect(
          DouradinhaGame.resolveTrickWinner(sameTeam, game.players)?.team, 0);
    });

    test('a maior carta abre a próxima mão e o empate mantém quem abriu', () {
      expect(
        DouradinhaGame.nextHandLeader(
          currentLeader: 0,
          winningPlayer: 4,
        ),
        4,
      );
      expect(
        DouradinhaGame.nextHandLeader(
          currentLeader: 3,
          winningPlayer: null,
        ),
        3,
      );
    });

    test('aplica os desempates da disputa', () {
      expect(DouradinhaGame.resolveDisputeWinner([0, null]), 0);
      expect(DouradinhaGame.resolveDisputeWinner([null, 1]), 1);
      expect(DouradinhaGame.resolveDisputeWinner([0, 1, null]), 0);
      expect(DouradinhaGame.resolveDisputeWinner([null, null, 1]), 1);
      expect(DouradinhaGame.resolveDisputeWinner([null, null, null]), isNull);
      expect(DouradinhaGame.resolveDisputeWinner([0, 1]), isNull);
    });

    test('separa os valores falados dos tentos marcados', () {
      expect(DouradinhaGame.nextChallengeAfter(1), 2);
      expect(DouradinhaGame.nextChallengeAfter(2), 3);
      expect(DouradinhaGame.nextChallengeAfter(3), 4);
      expect(DouradinhaGame.nextChallengeAfter(4), 6);
      expect(DouradinhaGame.nextChallengeAfter(6), isNull);
      expect(DouradinhaGame.spokenValueForPoints(1), 2);
      expect(DouradinhaGame.spokenValueForPoints(2), 4);
      expect(DouradinhaGame.spokenValueForPoints(3), 6);
      expect(DouradinhaGame.spokenValueForPoints(4), 9);
      expect(DouradinhaGame.spokenValueForPoints(6), 12);
    });

    test('alterna o direito de aumentar entre os trios', () {
      expect(
        DouradinhaGame.isChallengeTurnForTeam(
          team: 1,
          lastChallengeTeam: 1,
          handValue: 2,
        ),
        isFalse,
      );
      expect(
        DouradinhaGame.isChallengeTurnForTeam(
          team: 0,
          lastChallengeTeam: 1,
          handValue: 2,
        ),
        isTrue,
      );
      expect(
        DouradinhaGame.isChallengeTurnForTeam(
          team: 0,
          lastChallengeTeam: 0,
          handValue: 3,
        ),
        isFalse,
      );
      expect(
        DouradinhaGame.isChallengeTurnForTeam(
          team: 1,
          lastChallengeTeam: 0,
          handValue: 3,
        ),
        isTrue,
      );
    });

    test('mostra a resposta quando o adversário aceita ou corre', () {
      expect(
        DouradinhaGame.challengeNoticeDuration,
        const Duration(seconds: 2),
      );
      DouradinhaGame? gameWithNotice;
      for (var seed = 0; seed < 100; seed++) {
        final candidate = DouradinhaGame(random: Random(seed));
        candidate.requestHumanChallenge();
        candidate.resolveBotChallenge();
        if (candidate.challengeNotice != null) {
          gameWithNotice = candidate;
          break;
        }
      }

      expect(gameWithNotice, isNotNull);
      final resolvedGame = gameWithNotice!;
      expect(resolvedGame.challengeNotice, isNotEmpty);
      if (resolvedGame.challengeNoticeAccepted) {
        expect(resolvedGame.phase, MatchPhase.playing);
      } else {
        expect(resolvedGame.phase, MatchPhase.handFinished);
        expect(resolvedGame.lastHandWinner, 0);
      }
      resolvedGame.clearChallengeNotice();
      expect(resolvedGame.challengeNotice, isNull);
    });

    test('reserva ao humano todas as decisões de aposta do seu trio', () {
      expect(DouradinhaGame.botCanDecideChallengeForTeam(0), isFalse);
      expect(DouradinhaGame.botCanDecideChallengeForTeam(1), isTrue);
    });

    test('robô não desafia quando a Douradinha adversária já ganhou a mão', () {
      final game = DouradinhaGame(random: Random(23));
      game.currentPlayerIndex = 1;
      game.trickWinners.addAll([0, 1]);
      game.currentTrick.add(
        const PlayedCard(
          playerIndex: 0,
          card: PlayingCard('Q', 'o'),
        ),
      );

      game.takeBotTurn();

      expect(game.pendingChallenge, isNull);
      expect(game.lastChallengeTeam, isNull);
      expect(game.currentTrick, hasLength(2));
    });

    test('trio de robôs conversa e corre quando todos estão fracos', () {
      final game = DouradinhaGame(random: Random(29));
      for (final player in game.players.where((player) => player.team == 1)) {
        player.hand
          ..clear()
          ..addAll(const [
            PlayingCard('4', 'o'),
            PlayingCard('4', 'e'),
            PlayingCard('5', 'o'),
          ]);
      }

      game.requestHumanChallenge();
      game.resolveBotChallenge();

      expect(game.phase, MatchPhase.handFinished);
      expect(game.lastHandWinner, 0);
      expect(game.challengeNotice, contains('conversou e correu'));
    });

    test('trio não corre quando ceder os pontos encerra a partida', () {
      final game = DouradinhaGame(random: Random(37));
      game.scores[0] = 8;
      game.handValue = 4;
      game.lastChallengeTeam = 1;
      for (final player in game.players.where((player) => player.team == 1)) {
        player.hand
          ..clear()
          ..addAll(const [
            PlayingCard('4', 'o'),
            PlayingCard('4', 'e'),
            PlayingCard('5', 'o'),
          ]);
      }

      game.requestHumanChallenge();
      expect(game.pendingChallenge?.requestedValue, 6);
      game.resolveBotChallenge();

      expect(game.phase, MatchPhase.playing);
      expect(game.handValue, 6);
      expect(game.pendingChallenge, isNull);
      expect(game.challengeNoticeAccepted, isTrue);
      expect(game.challengeNotice, contains('aceitou'));
    });

    test('limita pedidos e aumentos dos robôs sem remover o blefe', () {
      final strongestOpening = DouradinhaGame.botProactiveChallengeProbability(
        raiseVotes: 3,
        acceptVotes: 0,
        tableIsEmpty: true,
        completedTricks: 0,
        handValue: 1,
      );
      final weakBluff = DouradinhaGame.botProactiveChallengeProbability(
        raiseVotes: 0,
        acceptVotes: 0,
        tableIsEmpty: true,
        completedTricks: 0,
        handValue: 1,
      );
      final strongestRaise = DouradinhaGame.botRaiseResponseProbability(
        raiseVotes: 3,
        acceptVotes: 0,
        requestedValue: 2,
      );

      expect(strongestOpening, lessThanOrEqualTo(.16));
      expect(weakBluff, greaterThan(0));
      expect(weakBluff, lessThan(.02));
      expect(strongestRaise, .26);
      expect(
        DouradinhaGame.botRaiseResponseProbability(
          raiseVotes: 3,
          acceptVotes: 0,
          requestedValue: 6,
        ),
        0,
      );
    });

    test('apoio forte pode aumentar, mas não aumenta automaticamente', () {
      var raises = 0;
      for (var seed = 0; seed < 100; seed++) {
        final game = DouradinhaGame(random: Random(seed));
        final strongCards = <int, List<PlayingCard>>{
          1: const [PlayingCard('Q', 'o')],
          3: const [PlayingCard('J', 'p')],
          5: const [PlayingCard('2', 'p')],
        };
        for (final entry in strongCards.entries) {
          game.players[entry.key].hand
            ..clear()
            ..addAll(entry.value);
        }

        game.requestHumanChallenge();
        game.resolveBotChallenge();
        if (game.humanMustAnswerChallenge) raises++;
      }

      expect(raises, greaterThan(10));
      expect(raises, lessThan(40));
    });

    test('trio considera o pedido somente uma vez em cada mão', () {
      DouradinhaGame? gameWithoutFirstRequest;
      for (var seed = 0; seed < 100; seed++) {
        final game = DouradinhaGame(random: Random(seed));
        game.playHumanCard(game.players[0].hand.first);
        game.takeBotTurn();
        if (game.pendingChallenge == null) {
          gameWithoutFirstRequest = game;
          break;
        }
      }

      final game = gameWithoutFirstRequest!;
      while (game.currentTrick.length < 6 && game.pendingChallenge == null) {
        game.takeBotTurn();
      }

      expect(game.pendingChallenge, isNull);
      expect(game.currentTrick, hasLength(6));
    });

    test('reduz o relógio individual após jogadas automáticas', () {
      expect(DouradinhaGame.timeLimitAfterTimeouts(0), 15);
      expect(DouradinhaGame.timeLimitAfterTimeouts(1), 12);
      expect(DouradinhaGame.timeLimitAfterTimeouts(2), 8);
      expect(DouradinhaGame.timeLimitAfterTimeouts(5), 8);

      final game = DouradinhaGame(random: Random(19));
      expect(game.currentPlayerIndex, 0);
      expect(game.players[0].hand, hasLength(3));

      game.autoPlayCurrentPlayerOnTimeout();

      expect(game.players[0].hand, hasLength(2));
      expect(game.timeoutCountFor(0), 1);
      expect(game.timeLimitSecondsFor(0), 12);
      expect(
        game.history.any((entry) => entry.contains('automaticamente')),
        isTrue,
      );
    });
  });

  testWidgets('abre a mesa com um humano e os cinco robôs', (tester) async {
    await tester.pumpWidget(const DouradinhaApp());
    await tester.pump();

    expect(find.text('VOCÊ'), findsOneWidget);
    for (var index = 1; index <= 5; index++) {
      expect(find.text('Robô $index'), findsOneWidget);
    }
    expect(find.text('TRUCO!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
