// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'test/kafka_connection_test.dart';  // 테스트 import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatDemoApp());
}

class ChatDemoApp extends StatelessWidget {
  const ChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat + Kafka Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}