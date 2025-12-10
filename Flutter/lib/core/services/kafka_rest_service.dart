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

      // ✅ 첫 폴링으로 partition assignment 완료 대기
      await _initialPoll();

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
          // ✅ Consumer 설정 추가
          'fetch.min.bytes': '1',
          'consumer.request.timeout.ms': '30000',
        }),
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        consumerInstanceId = data['instance_id'];
        consumerBaseUri = data['base_uri'];

        // base_uri 누락 시 fallback
        if (consumerBaseUri == null && consumerInstanceId != null) {
          consumerBaseUri =
          '$restProxyUrl/consumers/$consumerGroup/instances/$consumerInstanceId';
          print("⚠️ base_uri 누락 → fallback 생성: $consumerBaseUri");
        }

        print('✅ Consumer 생성: $consumerInstanceId');
        print('🔗 Consumer URI: $consumerBaseUri');
      } else {
        throw Exception('Consumer 생성 실패: ${response.statusCode}\n${response.body}');
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
        },
        body: jsonEncode({
          'topics': ['chat-responses'],
        }),
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✅ 토픽 구독 성공: chat-responses');
      } else {
        throw Exception('토픽 구독 실패: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      print('❌ 토픽 구독 에러: $e');
      rethrow;
    }
  }

  /// ✅ 초기 폴링 (Partition Assignment 대기)
  Future<void> _initialPoll() async {
    print('🔄 초기 폴링 (Partition Assignment)...');

    try {
      final response = await http
          .get(
        Uri.parse('$consumerBaseUri/records'),
        headers: {'Accept': 'application/vnd.kafka.json.v2+json'},
      )
          .timeout(const Duration(seconds: 10));

      print('✅ 초기 폴링 완료 (${response.statusCode})');

      // 첫 폴링은 보통 빈 배열이지만, partition assignment가 완료됨
      if (response.statusCode == 200) {
        final records = jsonDecode(response.body) as List;
        if (records.isNotEmpty) {
          print('⚡ 초기 폴링에서 ${records.length}개 메시지 발견!');
          // 초기 메시지 처리는 건너뜀 (latest offset이므로)
        }
      }
    } catch (e) {
      print('⚠️ 초기 폴링 에러 (무시 가능): $e');
    }

    // 추가 대기 시간 (안정화)
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// 질문 전송 (Producer)
  Future<String> sendQuestion(String question) async {
    if (!_isConnected) {
      throw Exception('REST Proxy 연결 필요');
    }

    final messageId = 'msg-${_uuid.v4()}';

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

    _pollingTimer = Timer.periodic(
      Duration(seconds: _pollingIntervalSeconds),
          (timer) async {
        if (!_isConnected || consumerBaseUri == null) {
          timer.cancel();
          return;
        }

        try {
          final response = await http
              .get(
            Uri.parse('$consumerBaseUri/records'),
            headers: {'Accept': 'application/vnd.kafka.json.v2+json'},
          )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final records = jsonDecode(response.body) as List;

            if (records.isNotEmpty) {
              print('📥 ${records.length}개 메시지 수신');

              for (var record in records) {
                final rawValue = record['value'];
                if (rawValue == null) continue;

                // value 처리 (List 또는 Map)
                List elements = [];
                if (rawValue is List) {
                  elements = rawValue;
                } else if (rawValue is Map) {
                  elements = [rawValue];
                }

                for (var element in elements) {
                  if (element is! Map) continue;

                  final typedValue = Map<String, dynamic>.from(element);

                  // UTF-8 복원
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
                  } else if (messageId != null) {
                    print("⚠️ 콜백 없음 (이미 처리됨?): $messageId");
                  }
                }
              }
            } else {
              // 메시지 없음 (정상)
              if (_callbacks.isNotEmpty) {
                print('⏳ 대기 중... (${_callbacks.length}개 콜백)');
              }
            }
          } else if (response.statusCode != 404) {
            print('⚠️ 폴링 응답: ${response.statusCode}');
          }
        } catch (e) {
          // 폴링 에러는 조용히 처리
          print('⚠️ 폴링 에러: $e');
        }
      },
    );
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
      return utf8.decode(input.codeUnits);
    } catch (_) {}

    return input;
  }
}