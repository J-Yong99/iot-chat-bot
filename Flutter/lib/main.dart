import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_markdown/flutter_markdown.dart';

void main() {
  runApp(const ChatDemoApp());
}

class ChatDemoApp extends StatelessWidget {
  const ChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat + STT Demo',
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
  final double? duration;
  final String? lang;

  Message({required this.text, required this.isMe, this.duration, this.lang});
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
  bool _isTyping = false;

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(Message(text: text, isMe: true));
      _isTyping = true;
    });

    _controller.clear();
    _scrollToBottom();

    final response = await _fakeApiCall(text);

    setState(() {
      _isTyping = false;
      _messages.add(
        Message(
          text: response["text"],
          isMe: false,
          duration: response["duration"],
          lang: response["lang"],
        ),
      );
    });

    _scrollToBottom();
  }

  /// 🔧 괄호 안 숫자도 마크다운이 정상 동작하도록 escape 처리
  String fixMarkdown(String text) {
    // 예: **소방서(119)** → **소방서\(119\)**
    return text.replaceAllMapped(
      RegExp(r'\*\*(.*?)\((.*?)\)\*\*'),
      (match) => '**${match.group(1)}\\(${match.group(2)}\\)**',
    );
  }

  Future<Map<String, dynamic>> _fakeApiCall(String userMessage) async {
    await Future.delayed(const Duration(seconds: 2));

    final Map<String, dynamic> fakeJsonResponse = {
      "status": 200,
      "lang": "ko",
      "data": {
        "text":
            "거실에 불이 났다면 즉시 **안전을 우선**으로 생각하세요.\n1. **구조를 위해 즉시 대피**하세요.\n2. **소화기**나 **화재 대응 방법**을 활용해 초기 진화를 시도할 수 있지만, **안전이 우선**입니다.\n3. **소방서(119)**에 신고하세요.\n\n만약 **실제로 불이 났다**고 느낀다면, 위의 절차를 따라주세요.\n다른 의미로 해석 될 수 있다면 추가 설명해 주세요! 🔥",
        "duration": 6.78,
      },
    };

    return {
      "text": fakeJsonResponse["data"]["text"],
      "duration": fakeJsonResponse["data"]["duration"],
      "lang": fakeJsonResponse["lang"],
    };
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

  /// 간단한 '**굵게**' 패턴만 감지하여 RichText로 표시
  Widget _buildRichText(String text, bool isMe) {
    final boldRegex = RegExp(r'\*\*(.*?)\*\*');
    final matches = boldRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          color: isMe ? Colors.white : Colors.black87,
          fontSize: 16,
        ),
      );
    }

    List<TextSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      // 일반 텍스트
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      // 굵은 부분
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

      lastIndex = match.end;
    }

    // 마지막 남은 텍스트
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: isMe ? Colors.white : Colors.black87,
          fontSize: 16,
        ),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _messages.length + (_isTyping ? 1 : 0);

    return Scaffold(
      appBar: AppBar(title: const Text('STT Chat Demo')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (_isTyping && index == itemCount - 1) {
                  return const _TypingIndicatorBubble();
                }

                final msg = _messages[index];
                final isBot = !msg.isMe;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRichText(msg.text, msg.isMe),
                        if (isBot && (msg.duration != null || msg.lang != null))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              "${msg.duration?.toStringAsFixed(2)}초 / 언어: ${msg.lang ?? '알 수 없음'}",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
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

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble();

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _dot1;
  late final Animation<double> _dot2;
  late final Animation<double> _dot3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _dot1 = Tween(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6)),
    );
    _dot2 = Tween(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8)),
    );
    _dot3 = Tween(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _dot(Animation<double> anim) => AnimatedBuilder(
    animation: anim,
    builder: (_, __) => Transform.translate(
      offset: Offset(0, anim.value),
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [_dot(_dot1), _dot(_dot2), _dot(_dot3)],
        ),
      ),
    );
  }
}
