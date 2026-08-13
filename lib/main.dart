import 'package:dourada/firebase_options.dart';
import 'package:dourada/ui/lobby_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }
  runApp(const DouradinhaApp());
}

class DouradinhaApp extends StatelessWidget {
  const DouradinhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Douradinha',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE9A23B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LobbyPage(),
    );
  }
}
