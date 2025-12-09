import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/api/chat_api.dart';
import '../models/message.dart'; // Message 모델이 별도 파일에 있다고 가정
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

  // [STT] SpeechToText 인스턴스 및 상태 변수
  late stt.SpeechToText _speech;
  bool _isListening = false;
  int? _sttProcessingMessageIndex;
  String? _lastRecognizedText;

  @override
  void initState() {
    super.initState();
    _initKafka();
    _speech = stt.SpeechToText();
  }

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

    // 텍스트 입력 모드일 때만 사용자 메시지 추가 및 입력 필드 비우기
    if (!isSttMode) {
      setState(() {
        _messages.add(Message(text: text, isMe: true));
      });
      _controller.clear();
    }

    // API 호출 전 타이핑 인디케이터 활성화
    setState(() {
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // Kafka 모드 선택
      final res = (_isKafkaMode && _isKafkaConnected)
          ? await ChatApi.sendQuestion(text)
          : await ChatApi.fakeSttApi(text);

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
          Message(text: "❌ 오류 발생: $e", isMe: false, duration: 0.0, lang: "ko"),
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

  // --------------------------------------------------
  // STT 로직 (speech_to_text 사용)
  // --------------------------------------------------

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
          // 음성 인식이 자동으로 끝났을 때만 처리
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
            // 실시간 피드백을 위해 임시 메시지를 업데이트합니다.
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

      // 임시 "듣는 중" 메시지 띄우기
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
      // 최종 인식된 텍스트로 STT 프로세스 시작
      _processStt(_lastRecognizedText!);
    } else {
      // 텍스트가 없으면 임시 메시지 제거
      _removeTempMessage();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('인식된 음성이 없습니다.')));
      }
    }
  }

  Future<void> _processStt(String transcribedText) async {
    // 1. 임시 메시지 업데이트 (STT 완료 상태로)
    _replaceTempMessage(transcribedText, isError: false, isRealtime: false);

    // 2. STT 완료 후 Kafka/Fake API 로직 실행
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
          // 실시간 업데이트 (Processing 상태 유지)
          _messages[_sttProcessingMessageIndex!] = currentMessage.copyWith(
            text: newText,
            isProcessing: true,
          );
        } else if (isError) {
          // 최종 에러 처리
          _messages[_sttProcessingMessageIndex!] = Message(
            text: "❌ $newText",
            isMe: false,
            duration: 0.0,
            lang: 'ko',
          );
        } else {
          // 최종 성공 처리 (Kafka 요청 준비)
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

  // --------------------------------------------------
  // UI 빌더
  // --------------------------------------------------

  Widget _buildInputWidget() {
    final showSendButton = _controller.text.trim().isNotEmpty || _isListening;

    return Container(
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
              onChanged: (text) => setState(() {}),
              onSubmitted: (text) => _sendMessage(text),
              // 녹음 중에는 텍스트 입력 비활성화
              enabled: !_isListening,
            ),
          ),

          if (showSendButton)
            // 보내기/정지 버튼
            IconButton(
              icon: Icon(
                _isListening ? Icons.stop_circle_outlined : Icons.send,
                color: _isListening ? Colors.red : Colors.blueAccent,
              ),
              // 녹음 중이면 중지 함수 호출, 아니면 보내기 함수 호출
              onPressed: _isListening
                  ? _stopListening
                  : () => _sendMessage(_controller.text),
            )
          else
            // 마이크 버튼
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.blueAccent),
              onPressed: _startListening,
            ),
        ],
      ),
    );
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
                            content: Text(
                              _isKafkaMode ? '🟢 Kafka 모드' : '🟠 Fake API 모드',
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    : null, // Kafka 연결 안 되면 비활성화
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
                ? (_isKafkaMode
                      ? Colors.green.shade100
                      : Colors.orange.shade100)
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
          _buildInputWidget(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    ChatApi.dispose();
    _speech.stop(); // STT 리소스 정리
    super.dispose();
  }
}
