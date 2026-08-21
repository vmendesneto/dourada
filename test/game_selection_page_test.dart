import 'package:dourada/main.dart';
import 'package:dourada/online/lobby_service.dart';
import 'package:dourada/ui/game_selection_page.dart';
import 'package:dourada/ui/lobby_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';

void main() {
  testWidgets('seleciona Dourada Interior antes de abrir o lobby', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      DouradinhaApp(
        authService: FakeAuthService(signedIn: true),
        lobbyService: LobbyService(serverUrl: ''),
      ),
    );

    expect(find.byType(GameSelectionPage), findsOneWidget);
    expect(find.text('Dourada Interior'), findsOneWidget);
    expect(find.byKey(const ValueKey('entrar-em-uma-mesa')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('abrir-dourada-interior')));
    await tester.pumpAndSettle();

    expect(find.byType(LobbyPage), findsOneWidget);
    expect(find.byKey(const ValueKey('entrar-em-uma-mesa')), findsOneWidget);
    expect(find.byKey(const ValueKey('voltar-aos-jogos')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('voltar-aos-jogos')));
    await tester.pumpAndSettle();

    expect(find.byType(GameSelectionPage), findsOneWidget);
    expect(find.text('Dourada Interior'), findsOneWidget);
  });
}
