// lib/core/services/kafka_rest_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class KafkaRestService {
  static const String restProxyUrl = 'http://118.36.36.206:8082';
  static String consumerGroup = 'flutter-${Uuid().v4()}';

  String? currentUserId;
  String? consumerInstanceId;
  String? consumerBaseUri;

  final Map<String, Function(Map<String, dynamic>)> _callbacks = {};
  final _uuid = const Uuid();

  Timer? _pollingTimer;
  bool _isConnected = false;
  int _pollingIntervalSeconds = 2;

  // 싱글톤
  static final KafkaRestService _instance = KafkaRestService._internal();
  factory KafkaRestService() => _instance;
  KafkaRestService._internal();

  Future<void> init(String userId) async {
    currentUserId = userId;

    try {
      print('📡 REST Proxy 연결 시도: $restProxyUrl');

      // 연결 테스트
      final testResponse = await http
          .get(Uri.parse('$restProxyUrl/topics'))
          .timeout(const Duration(seconds: 5));

      if (testResponse.statusCode != 200) {
        throw Exception('REST Proxy 응답 실패: ${testResponse.statusCode}');
      }

      print('✅ REST Proxy 연결 확인');

      // Consumer 인스턴스 생성
      await _createConsumerInstance();

      // 토픽 구독
      await _subscribeToTopics();

      // 폴링 시작
      _startPolling();

      _isConnected = true;
      print('✅ Kafka REST Proxy 초기화 완료');
    } catch (e) {
      print('❌ REST Proxy 연결 실패: $e');
      _isConnected = false;
      rethrow;
    }
  }

  /// Consumer 인스턴스 생성
  Future<void> _createConsumerInstance() async {
    final instanceName =
        'flutter-$currentUserId-${DateTime.now().millisecondsSinceEpoch}';

    try {
      print("🛰 consumer base_uri: $consumerBaseUri");

      final response = await http
          .post(
            Uri.parse('$restProxyUrl/consumers/$consumerGroup'),
            headers: {
              'Content-Type': 'application/vnd.kafka.v2+json',
              'Accept': 'application/vnd.kafka.v2+json',
            },
            body: jsonEncode({
              'name': instanceName,
              'format': 'json',
              'auto.offset.reset': 'latest',
              'auto.commit.enable': 'true',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        consumerInstanceId = data['instance_id'];
        consumerBaseUri = data['base_uri'];

        // 🔥🔥🔥 정확한 위치: instance_id 세팅 직후
        if (consumerBaseUri == null && consumerInstanceId != null) {
          consumerBaseUri =
              '$restProxyUrl/consumers/$consumerGroup/instances/$consumerInstanceId';
          print("⚠️ base_uri 누락 → fallback 생성: $consumerBaseUri");
        }
        print('🔥 Consumer 생성 raw response: ${response.body}');
        print('🔥 instance_id 파싱 결과: $consumerInstanceId');
        print('🔥 base_uri 파싱 결과: $consumerBaseUri');
        print('✅ Consumer 생성: $consumerInstanceId');
      } else {
        throw Exception('Consumer 생성 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Consumer 생성 에러: $e');
      rethrow;
    }
  }

  /// 토픽 구독
  Future<void> _subscribeToTopics() async {
    try {
      final response = await http
          .post(
            Uri.parse('$consumerBaseUri/subscription'),
            headers: {
              'Content-Type': 'application/vnd.kafka.v2+json',
              'Accept': 'application/vnd.kafka.v2+json', // ★ 중요
            },
            body: jsonEncode({
              'topics': ['chat-responses'],
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✅ 토픽 구독 성공: chat-responses');
      } else {
        throw Exception('토픽 구독 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 토픽 구독 에러: $e');
      rethrow;
    }
  }

  /// 질문 전송 (Producer)
  Future<String> sendQuestion(String question) async {
    if (!_isConnected) {
      throw Exception('REST Proxy 연결 필요');
    }

    final messageId = 'msg-${_uuid.v4()}';
    // final messageId = 'msg-1';

    final message = {
      'message_id': messageId,
      'user_id': currentUserId,
      'question': question,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': {'platform': 'flutter', 'language': 'ko'},
    };

    try {
      final response = await http
          .post(
            Uri.parse('$restProxyUrl/topics/chat-requests'),
            headers: {'Content-Type': 'application/vnd.kafka.json.v2+json'},
            body: jsonEncode({
              'records': [
                {'key': currentUserId, 'value': message},
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('📤 메시지 전송 성공: $messageId');
        return messageId;
      } else {
        throw Exception('전송 실패: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('❌ 메시지 전송 에러: $e');
      rethrow;
    }
  }

  /// 콜백 등록
  void registerCallback(
    String messageId,
    Function(Map<String, dynamic>) callback,
  ) {
    _callbacks[messageId] = callback;
    print('📝 콜백 등록: $messageId (대기 중: ${_callbacks.length}개)');
  }

  /// 폴링 시작
  void _startPolling() {
    print('🔄 폴링 시작 ($_pollingIntervalSeconds초 간격)');

    _pollingTimer = Timer.periodic(Duration(seconds: _pollingIntervalSeconds), (
      timer,
    ) async {
      if (!_isConnected || consumerBaseUri == null) {
        timer.cancel();
        return;
      }

      if (_callbacks.isEmpty) {
        // 대기 중인 메시지 없으면 폴링 스킵
        return;
      }

      try {
        final response = await http
            .get(
              Uri.parse('$consumerBaseUri/records'),
              headers: {'Accept': 'application/vnd.kafka.json.v2+json'},
            )
            .timeout(const Duration(seconds: 5));

        print("📥 폴링 응답 상태코드: ${response.statusCode}");

        // 응답 RAW 데이터 출력
        print("📭 RAW 응답 데이터: ${response.body}");

        if (response.statusCode == 200) {
          final records = jsonDecode(response.body) as List;

          if (records.isNotEmpty) {
            print('📥 ${records.length}개 메시지 수신');
            for (var record in records) {
              final rawValue = record['value'];

              if (rawValue == null) return;

              // value가 배열이 아니라 단일 객체(Map)인 경우 처리
              List elements = [];
              if (rawValue is List) {
                elements = rawValue;
              } else if (rawValue is Map) {
                elements = [rawValue];
              }

              for (var element in elements) {
                if (element is! Map) continue;

                final typedValue = Map<String, dynamic>.from(element);

                // 🔧 UTF-8 복원 대상 필드들
                void restoreUtf8(String key) {
                  if (typedValue[key] is String) {
                    typedValue[key] = fixUtf8(typedValue[key]);
                  }
                }

                restoreUtf8("answer");
                restoreUtf8("text");
                restoreUtf8("response");
                restoreUtf8("message_id");
                restoreUtf8("user_id");

                final messageId = typedValue['message_id'];
                if (messageId != null && _callbacks.containsKey(messageId)) {
                  print("🎯 콜백 실행: $messageId");
                  _callbacks[messageId]!(typedValue);
                  _callbacks.remove(messageId);
                }
              }
            }
          }
        } else if (response.statusCode != 404) {
          // 404는 메시지 없음 (정상), 다른 에러만 로그
          print('⚠️ 폴링 응답: ${response.statusCode}');
        }
      } catch (e) {
        // 폴링 에러는 조용히 무시 (다음 주기 재시도)
        // print('⚠️ 폴링 에러: $e');
      }
    });
  }

  bool get isConnected => _isConnected;

  /// 리소스 정리
  Future<void> dispose() async {
    print('🧹 REST Proxy 리소스 정리');

    _pollingTimer?.cancel();
    _callbacks.clear();

    // Consumer 인스턴스 삭제
    if (consumerBaseUri != null) {
      try {
        await http.delete(Uri.parse(consumerBaseUri!));
        print('✅ Consumer 인스턴스 삭제');
      } catch (e) {
        print('⚠️ Consumer 삭제 실패: $e');
      }
    }

    _isConnected = false;
    consumerInstanceId = null;
    consumerBaseUri = null;
  }

  String fixUtf8(String input) {
    try {
      return utf8.decode(input.runes.toList());
    } catch (_) {}

    try {
      // Latin-1 → UTF-8 재해석
      return utf8.decode(input.codeUnits);
    } catch (_) {}

    return input; // 실패하면 원본
  }
}
