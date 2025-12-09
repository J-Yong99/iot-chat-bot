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

    // 말풍선 색상 설정
    final bubbleColor = message.isMe
        ? Colors.blueAccent
        : (message.isProcessing ? Colors.grey.shade400 : Colors.grey.shade300);

    // 텍스트 색상 설정
    final textColor = message.isMe ? Colors.white : Colors.black87;

    // ----------------------------------------------------
    // 공통 말풍선 (Bubble Content)
    // ----------------------------------------------------
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // 텍스트와 로딩 인디케이터를 한 줄에 표시
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 메시지 텍스트
              Flexible(child: buildRichText(message.text, message.isMe)),

              // 2. STT 처리 중 로딩 인디케이터 (추가)
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

          // 3. 봇 메시지 상세 정보 (Duration, Lang)
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
    // ----------------------------------------------------

    // 봇 메시지 (왼쪽)
    if (isBot) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BotAvatar(), // ✅ 봇 프로필 다시 추가!
            const SizedBox(width: 10),
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
          // 내 메시지 오른쪽에는 아바타가 없으므로 SizedBox(width: 10)을 유지하거나 제거할 수 있습니다.
          // 일관성을 위해 10 간격을 유지합니다.
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
