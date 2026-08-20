import 'package:dourada/online/chat_moderation.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mantém a inicial e mascara o restante dos palavrões', () {
    expect(
      moderateChatText('Porra! Isso é uma merda; foda-se.'),
      'P****! Isso é uma m****; f******.',
    );
    expect(
      moderateChatText('DESGRAÇADO, vai tomar no cu!'),
      'D*********, vai tomar no c*!',
    );
  });

  test('não mascara trechos dentro de palavras normais', () {
    expect(
      moderateChatText('O computador disputa a partida.'),
      'O computador disputa a partida.',
    );
  });

  test('mascara mensagens antigas recebidas no histórico', () {
    final messages = TableChatMessage.listFromJson([
      {
        'id': 'antiga-1',
        'seatIndex': 1,
        'author': 'Jogador',
        'text': 'Que merda!',
        'sentAt': 1000,
      },
    ]);

    expect(messages.single.text, 'Que m****!');
  });
}
