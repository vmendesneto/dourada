import 'package:dourada/ui/game_page.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const GamePage(),
    );
  }
}
