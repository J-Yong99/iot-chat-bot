import 'package:flutter/material.dart';
import '../core/utils/markdown_utils.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isBot = !message.isMe;

    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: message.isMe ? Colors.blueAccent : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}
