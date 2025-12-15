// lib/widgets/chat_bubble.dart 전체 코드 수정 (ScaleTransition 위치 변경)

import 'package:flutter/material.dart';
import '../core/utils/markdown_utils.dart';
import '../models/message.dart';
import 'bot_avatar.dart';

class ChatBubble extends StatefulWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isBot = !message.isMe;

    final bubbleColor = message.isMe
        ? Colors.blueAccent
        : (message.isProcessing ? Colors.grey.shade400 : Colors.grey.shade300);

    final bubbleContent = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 메시지 텍스트
              Flexible(child: buildRichText(message.text, message.isMe)),

              // 2. STT 처리 중 로딩 인디케이터
              if (message.isProcessing)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: message.isMe ? Colors.white : Colors.blueAccent,
                      strokeWidth: 2,
                    ),
                  ),
                ),
            ],
          ),

          // 3. 봇 메시지 상세 정보
          if (isBot &&
              (message.duration != null || message.lang != null) &&
              !message.isProcessing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "${message.duration?.toStringAsFixed(2)}초 / 언어: ${message.lang ?? '알 수 없음'}",
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
        ],
      ),
    );

    // 💡 [수정] ScaleTransition을 Row 전체가 아닌 말풍선 위젯에만 적용
    final animatedBubble = ScaleTransition(
      scale: _animation,
      // 봇 메시지는 왼쪽 위, 내 메시지는 오른쪽 위를 기준으로 확대
      alignment: isBot ? Alignment.topLeft : Alignment.topRight,
      child: bubbleContent,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: isBot
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 봇 메시지 (아바타 고정)
          if (isBot) ...[
            const BotAvatar(), // 아바타는 ScaleTransition 밖에 있습니다.
            const SizedBox(width: 10),
            Flexible(child: animatedBubble), // 말풍선에만 애니메이션 적용
          ],

          // 내 메시지
          if (!isBot) ...[
            Flexible(child: animatedBubble), // 말풍선에만 애니메이션 적용
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}
