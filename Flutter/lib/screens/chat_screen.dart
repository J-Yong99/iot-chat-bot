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

  // 💡 샘플 질문 정의
  final List<String> _sampleQuestions = const [
    "오늘의 날씨 알려줘",
    "이 코드가 하는 역할이 뭐야?",
    "Kafka가 무엇인지 설명해줘",
  ];

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

      // 💡 [수정] 메시지 전송 후 포커스가 해제되었다면 다시 잡아줍니다.
      if (!_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    }

    // 2. 봇 응답을 위한 로딩 메시지 추가
    final loadingMessage = Message(
      text: "...",
      isMe: false,
      isProcessing: true, // 로딩 상태
    );

    setState(() {
      _messages.add(loadingMessage);
    });
    _scrollToBottom();

    // 응답 메시지의 인덱스를 저장하여 나중에 이 위치를 덮어씁니다.
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

  // --------------------------------------------------
  // UI 빌더
  // --------------------------------------------------

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

  // lib/screens/chat_screen.dart 내의 _buildInputAndMicButton 함수 (수정)

  Widget _buildInputAndMicButton() {
    final hasText = _controller.text.trim().isNotEmpty;

    return GestureDetector(
      onTap: () {
        // 이 영역을 탭하면 포커스 해제를 막고, 포커스가 있다면 유지합니다.
        FocusScope.of(context).requestFocus(_focusNode);
      },
      child: Container(
        // Container를 사용하여 탭 영역을 확실히 정의
        color: Colors.transparent, // 탭 영역 확장
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
                      // ... (TextField 내부 내용은 유지)
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
                  backgroundColor: _isListening
                      ? Colors.red
                      : Colors.blueAccent,
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
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  // 💡 초기 환영 화면: 메시지가 비어있을 때 표시
  Widget _buildInitialWelcomeView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 20.0),
            child: Icon(Icons.android, size: 48, color: Colors.blueAccent),
          ),
          // 샘플 질문 버튼 목록 (크게)
          ..._sampleQuestions.map((question) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: ElevatedButton(
                onPressed: () {
                  _sendMessage(question);
                  // 💡 [추가] 초기 화면에서 질문 전송 시 포커스 활성화
                  FocusScope.of(context).requestFocus(_focusNode);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                child: Text(question, style: const TextStyle(fontSize: 15)),
              ),
            );
          }).toList(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // 💡 하단 샘플 질문: 메시지가 있을 때 키보드가 닫혀있으면 표시 (가로 스크롤, 그림자 적용)
  Widget _buildSampleQuestions() {
    return Container(
      // 배경을 투명하게 유지하여 아래 배경색(grey.shade100)이 보이도록 함
      decoration: const BoxDecoration(color: Colors.transparent),
      // 실제 콘텐츠가 들어갈 영역 (스크롤 가능하도록)
      child: Container(
        height: 70,
        color: Colors.transparent, // 투명 유지
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _sampleQuestions.length,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          itemBuilder: (context, index) {
            final question = _sampleQuestions[index];
            return Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: ActionChip(
                onPressed: () {
                  _sendMessage(question);
                  // 💡 [수정] 샘플 질문 클릭 시 포커스 활성화
                  FocusScope.of(context).requestFocus(_focusNode);
                },
                label: Text(
                  question,
                  // 💡 [수정] 흰색 배경에 검은색 글씨
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // 💡 [수정] 배경색: 흰색
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  // 💡 [수정] 테두리 제거 (그림자로 떠있는 느낌 대체)
                  side: BorderSide(color: Colors.grey.shade200, width: 0.5),
                ),
                elevation: 4, // 칩 자체에 그림자 추가
                shadowColor: Colors.black.withOpacity(0.2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          },
        ),
      ),
    );
  }

  // lib/screens/chat_screen.dart 내의 build 함수 (최종 수정)

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible =
        MediaQuery.of(context).viewInsets.bottom > 0.0;

    final itemCount = _messages.length;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      // 🔑 [수정] Scaffold 아래에 직접 GestureDetector를 두지 않고 Stack으로 시작합니다.
      body: Stack(
        children: [
          Column(
            children: [
              // 상단 iOS 스타일 헤더
              _buildTopHeader(),

              // 메시지가 없을 때 초기 환영 화면
              if (_messages.isEmpty)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: _buildInitialWelcomeView(),
                    ),
                  ),
                )
              else
                // 메시지 리스트 영역
                Expanded(
                  // 💡 [수정] ListView.builder를 바로 둠. 포커스 해제는 Stack의 Positioned 위젯으로 처리.
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: (!isKeyboardVisible && _messages.isNotEmpty)
                          ? 155.0
                          : 0.0,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        final message = _messages[index];

                        if (!message.isMe && message.isProcessing) {
                          return const TypingIndicator();
                        }

                        return ChatBubble(message: message);
                      },
                    ),
                  ),
                ),
            ],
          ),

          // 🔑 [추가] 키보드 해제 전용 GestureDetector를 Positioned로 ListView 영역에 덮어씁니다.
          // 이 GestureDetector가 _buildInputAndMicButton 위에 위치하지 않도록 주의합니다.
          if (isKeyboardVisible)
            Positioned.fill(
              top: 0,
              bottom:
                  MediaQuery.of(context).size.height -
                  (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom) -
                  80, // 입력창 높이(대략 80)를 제외한 나머지 영역
              child: GestureDetector(
                behavior: HitTestBehavior.translucent, // 탭 이벤트를 확실히 잡음
                onTap: _dismissKeyboard,
              ),
            ),

          // ⬇️ 하단 샘플 질문
          if (!isKeyboardVisible && _messages.isNotEmpty)
            Positioned(
              bottom: 75.0,
              left: 0,
              right: 0,
              child: _buildSampleQuestions(),
            ),

          // ⬇️ 입력창
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildInputAndMicButton(),
          ),
        ],
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
