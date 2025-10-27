class Message {
  final String text;
  final bool isMe;
  final double? duration;
  final String? lang;

  Message({required this.text, required this.isMe, this.duration, this.lang});
}
