import 'package:flutter/material.dart';

/// '**소방서(119)**' 같은 경우를 위해 괄호 자동 escape
String fixMarkdown(String text) {
  return text.replaceAllMapped(
    RegExp(r'\*\*(.*?)\((.*?)\)\*\*'),
    (match) => '**${match.group(1)}\\(${match.group(2)}\\)**',
  );
}

Widget buildRichText(String text, bool isMe) {
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
    if (match.start > lastIndex) {
      spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
    }

    spans.add(
      TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    lastIndex = match.end;
  }

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
