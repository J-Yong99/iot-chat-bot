import 'package:flutter/material.dart';
import '../core/utils/markdown_utils.dart';
import '../models/message.dart';
import 'bot_avatar.dart';

class ChatBubble extends StatelessWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isBot = !message.isMe;

    // 공통 말풍선
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: message.isMe ? Colors.blueAccent : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildRichText(message.text, message.isMe),
          if (isBot && (message.duration != null || message.lang != null))
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

    // 봇 메시지 (왼쪽)에서 BotAvatar 제거
    if (isBot) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BotAvatar 제거
            const SizedBox(width: 10),  // 간격만 남기고 아바타 삭제
            Flexible(child: bubble),
          ],
        ),
      );
    }

    // 내 메시지 (오른쪽)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(child: bubble),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
