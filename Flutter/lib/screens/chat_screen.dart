import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

  // 포커스/입력 상태 제어
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  bool _isKafkaMode = false;
  bool _isKafkaConnected = false;
  String _connectionStatus = '연결 중...';

  // [STT] SpeechToText 인스턴스 및 상태 변수
  late stt.SpeechToText _speech;
  bool _isListening = false;
  int? _sttProcessingMessageIndex;
  String? _lastRecognizedText;

  // 💡 _responseIndexMap은 이제 _sendMessage 함수 내부에서 로컬로 관리되므로 클래스 멤버에서 제거했습니다.

  @override
  void initState() {
    super.initState();
    _initKafka();
    _speech = stt.SpeechToText();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  // --- 핵심 로직 ---

  Future<void> _initKafka() async {
    setState(() {
      _connectionStatus = '연결 중...';
    });

    try {
      await ChatApi.init(
        'user-flutter-${DateTime.now().millisecondsSinceEpoch}',
      );

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kafka 연결 실패: Fake API 모드로 전환합니다'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage(String text, {bool isSttMode = false}) async {
    if (text.trim().isEmpty) return;

    // 1. 사용자 질문 메시지 추가
    if (!isSttMode) {
      setState(() {
        _messages.add(Message(text: text, isMe: true));
      });
      _controller.clear();
    }

    // 2. 봇 응답을 위한 로딩 메시지 추가 (TypingIndicator를 표시할 자리)
    final loadingMessage = Message(
      text: "...",
      isMe: false,
      isProcessing: true, // 로딩 상태
    );

    setState(() {
      _messages.add(loadingMessage);
    });
    _scrollToBottom();

    // 💡 [핵심] 응답 메시지의 인덱스를 저장하여 나중에 이 위치를 덮어씁니다.
    final responseIndex = _messages.length - 1;

    try {
      final res = (_isKafkaMode && _isKafkaConnected)
          ? await ChatApi.sendQuestion(text)
          : await ChatApi.fakeSttApi(text);

      setState(() {
        // 해당 인덱스의 메시지를 최종 답변으로 업데이트
        _messages[responseIndex] = Message(
          text: res["text"],
          isMe: false,
          duration: res["duration"],
          lang: res["lang"],
          isProcessing: false,
        );
      });
    } catch (e) {
      setState(() {
        // 오류 발생 시에도 해당 인덱스의 메시지를 업데이트
        _messages[responseIndex] = Message(
          text: "❌ 오류 발생: $e",
          isMe: false,
          duration: 0.0,
          lang: "ko",
          isProcessing: false,
        );
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // STT 로직 (생략 없이 유지)

  Future<void> _startListening() async {
    if (_isListening) {
      _stopListening();
      return;
    }

    bool available = await _speech.initialize(
      onError: (val) => print("STT Error: ${val.errorMsg}"),
      onStatus: (val) {
        if (val == stt.SpeechToText.notListeningStatus &&
            _isListening &&
            _lastRecognizedText != null) {
          _processStt(_lastRecognizedText!);
        }
      },
    );

    if (available) {
      setState(() {
        _isListening = true;
        _lastRecognizedText = null;
        FocusScope.of(context).unfocus();
      });

      _speech.listen(
        localeId: 'ko-KR',
        onResult: (val) {
          if (val.finalResult) {
            _lastRecognizedText = val.recognizedWords;
            _replaceTempMessage(
              "🎤 ${val.recognizedWords}",
              isError: false,
              isRealtime: true,
            );
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      );

      final tempMessage = Message(
        text: "🎤 듣는 중...",
        isMe: true,
        isProcessing: true,
      );

      setState(() {
        _messages.add(tempMessage);
        _sttProcessingMessageIndex = _messages.length - 1;
      });
      _scrollToBottom();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음성 인식을 시작할 수 없습니다. 권한을 확인하세요.')),
        );
      }
    }
  }

  void _stopListening() {
    if (!_isListening) return;

    _speech.stop();

    setState(() {
      _isListening = false;
    });

    if (_lastRecognizedText != null && _lastRecognizedText!.trim().isNotEmpty) {
      _processStt(_lastRecognizedText!);
    } else {
      _removeTempMessage();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('인식된 음성이 없습니다.')));
      }
    }
  }

  Future<void> _processStt(String transcribedText) async {
    _replaceTempMessage(transcribedText, isError: false, isRealtime: false);
    await _sendMessage(transcribedText, isSttMode: true);
  }

  void _replaceTempMessage(
    String newText, {
    required bool isError,
    required bool isRealtime,
  }) {
    if (_sttProcessingMessageIndex != null &&
        _sttProcessingMessageIndex! < _messages.length) {
      setState(() {
        final currentMessage = _messages[_sttProcessingMessageIndex!];

        if (isRealtime) {
          _messages[_sttProcessingMessageIndex!] = currentMessage.copyWith(
            text: newText,
            isProcessing: true,
          );
        } else if (isError) {
          _messages[_sttProcessingMessageIndex!] = Message(
            text: "❌ $newText",
            isMe: false,
            duration: 0.0,
            lang: 'ko',
          );
        } else {
          _messages[_sttProcessingMessageIndex!] = Message(
            text: newText,
            isMe: true,
          );
        }
      });
      _scrollToBottom();
    }
  }

  void _removeTempMessage() {
    if (_sttProcessingMessageIndex != null &&
        _sttProcessingMessageIndex! < _messages.length) {
      setState(() {
        _messages.removeAt(_sttProcessingMessageIndex!);
        _sttProcessingMessageIndex = null;
      });
      _scrollToBottom();
    }
  }

  // --- UI 빌더 ---

  Widget _buildTopHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.only(
        top: 8.0,
        bottom: 8.0,
        left: 16.0,
        right: 16.0,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildNavigationActions(),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildConnectionStatus(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _isKafkaMode ? 'Kafka' : 'Demo',
          style: const TextStyle(fontSize: 14, color: Colors.black54),
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
                      content: Text(
                        _isKafkaMode ? '🟢 Kafka 모드' : '🟠 Fake API 모드',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              : null,
          activeColor: Colors.blueAccent,
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    final statusColor = _isKafkaConnected
        ? (_isKafkaMode ? Colors.green.shade700 : Colors.orange.shade700)
        : Colors.red.shade700;

    final statusText = _isKafkaMode && _isKafkaConnected
        ? '🟢 Kafka 연결'
        : _isKafkaConnected
        ? '🟠 Local 모드'
        : '🔴 $_connectionStatus';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            statusText,
            style: TextStyle(fontSize: 12, color: statusColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInputAndMicButton() {
    final hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: (_isFocused || hasText)
                          ? ''
                          : 'message or voice',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 8,
                      ),
                    ),
                    onChanged: (text) => setState(() {}),
                    onSubmitted: (text) => _sendMessage(text),
                    enabled: !_isListening,
                    maxLines: 1,
                    minLines: 1,
                    textAlign: (_isFocused || hasText)
                        ? TextAlign.left
                        : TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            SizedBox(
              height: 48,
              width: 48,
              child: FloatingActionButton(
                onPressed: () {
                  if (_isListening) {
                    _stopListening();
                  } else if (hasText) {
                    _sendMessage(_controller.text);
                  } else {
                    _startListening();
                  }
                },
                elevation: 4,
                backgroundColor: _isListening ? Colors.red : Colors.blueAccent,
                child: Icon(
                  _isListening
                      ? Icons.stop_circle_outlined
                      : (hasText ? Icons.send : Icons.mic),
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _messages.length;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100, // 예: F5F5F5
        body: Stack(
          children: [
            Column(
              children: [
                _buildTopHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 75.0),
                    child: ListView.builder(
                      reverse: false,
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        final message = _messages[index];

                        if (!message.isMe && message.isProcessing) {
                          // 봇이 로딩 중일 때 TypingIndicator 표시
                          return const TypingIndicator();
                        }

                        // 일반 메시지 또는 응답 완료된 봇 메시지 표시
                        return ChatBubble(message: message);
                      },
                    ),
                  ),
                ),
              ],
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildInputAndMicButton(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    ChatApi.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }
}
