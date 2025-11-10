// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import '../core/api/chat_api.dart';
import '../models/message.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isKafkaMode = false;
  bool _isKafkaConnected = false;
  String _connectionStatus = '연결 중...';

  @override
  void initState() {
    super.initState();
    _initKafka();
  }

  Future<void> _initKafka() async {
    setState(() {
      _connectionStatus = '연결 중...';
    });

    try {
      await ChatApi.init('user-flutter-${DateTime.now().millisecondsSinceEpoch}');

      setState(() {
        _isKafkaConnected = true;
        _connectionStatus = 'Kafka 연결됨';
      });

      print('✅ Kafka 초기화 완료');

    } catch (e) {
      setState(() {
        _isKafkaConnected = false;
        _connectionStatus = '연결 실패: $e';
      });

      print('❌ Kafka 초기화 실패: $e');

      // 사용자에게 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kafka 연결 실패: Fake API 모드로 전환합니다'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(Message(text: text, isMe: true));
      _isTyping = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      // Kafka 모드 선택
      final res = (_isKafkaMode && _isKafkaConnected)
          ? await ChatApi.sendQuestion(text)  // 실제 Kafka
          : await ChatApi.fakeSttApi(text);   // Fake API

      setState(() {
        _isTyping = false;
        _messages.add(
          Message(
            text: res["text"],
            isMe: false,
            duration: res["duration"],
            lang: res["lang"],
          ),
        );
      });
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add(
          Message(
            text: "❌ 오류 발생: $e",
            isMe: false,
            duration: 0.0,
            lang: "ko",
          ),
        );
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _messages.length + (_isTyping ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('STT Chat Demo'),
        actions: [
          // Kafka 모드 토글
          Row(
            children: [
              Text(
                _isKafkaMode ? 'Kafka' : 'Fake',
                style: const TextStyle(fontSize: 12),
              ),
              Switch(
                value: _isKafkaMode,
                onChanged: _isKafkaConnected
                    ? (value) {
                  setState(() {
                    _isKafkaMode = value;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isKafkaMode ? '🟢 Kafka 모드' : '🟠 Fake API 모드'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
                    : null,  // Kafka 연결 안 되면 비활성화
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 연결 상태 표시
          Container(
            padding: const EdgeInsets.all(8),
            color: _isKafkaConnected
                ? (_isKafkaMode ? Colors.green.shade100 : Colors.orange.shade100)
                : Colors.red.shade100,
            child: Row(
              children: [
                Icon(
                  _isKafkaConnected
                      ? (_isKafkaMode ? Icons.cloud_queue : Icons.cloud_off)
                      : Icons.error_outline,
                  size: 16,
                  color: _isKafkaConnected
                      ? (_isKafkaMode ? Colors.green : Colors.orange)
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isKafkaMode && _isKafkaConnected
                        ? '🟢 Kafka 실시간 연결'
                        : _isKafkaConnected
                        ? '🟠 로컬 모드 (Fake API)'
                        : '🔴 $_connectionStatus',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (!_isKafkaConnected)
                  TextButton(
                    onPressed: _initKafka,
                    child: const Text('재연결', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (_isTyping && index == itemCount - 1) {
                  return const TypingIndicator();
                }
                return ChatBubble(message: _messages[index]);
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

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    ChatApi.dispose();
    super.dispose();
  }
}