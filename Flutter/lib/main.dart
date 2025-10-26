import 'package:flutter/material.dart';
import 'dart:async'; // Timer 사용

void main() {
  runApp(const ChatDemoApp());
}

class ChatDemoApp extends StatelessWidget {
  const ChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class Message {
  final String text;
  final bool isMe;
  Message({required this.text, required this.isMe});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(Message(text: text, isMe: true));
    });

    _controller.clear();
    _scrollToBottom();

    // 실제로는 여기서 API 요청을 보낸다고 가정
    Future.delayed(const Duration(milliseconds: 800), () {
      _fakeResponse(text);
    });
  }

  void _fakeResponse(String userMessage) {
    final String reply = _generateFakeReply(userMessage);

    setState(() {
      _messages.add(Message(text: reply, isMe: false));
    });

    _scrollToBottom();
  }

  String _generateFakeReply(String text) {
    // 간단한 데모용 응답 로직
    if (text.contains("안녕")) return "안녕하세요! 만나서 반가워요 😊";
    if (text.contains("이름")) return "저는 데모봇이에요 🤖";
    if (text.contains("시간"))
      return "지금은 ${DateTime.now().hour}시 ${DateTime.now().minute}분이에요!";
    return "그건 흥미롭네요!";
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Demo')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: msg.isMe
                          ? Colors.blueAccent
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isMe ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
