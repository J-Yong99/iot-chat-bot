class Message {
  final String text;
  final bool isMe;
  final double? duration;
  final String? lang;
  final bool isProcessing; // 임시 메시지 구별 플래그

  Message({
    required this.text,
    required this.isMe,
    this.duration,
    this.lang,
    this.isProcessing = false,
  });

  // 💡 실시간 업데이트를 위한 copyWith 추가 (선택 사항이지만 유용)
  Message copyWith({
    String? text,
    bool? isMe,
    double? duration,
    String? lang,
    bool? isProcessing,
  }) {
    return Message(
      text: text ?? this.text,
      isMe: isMe ?? this.isMe,
      duration: duration ?? this.duration,
      lang: lang ?? this.lang,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}
