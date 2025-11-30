// lib/core/api/chat_api.dart
import 'dart:async';
import '../services/kafka_rest_service.dart';

class ChatApi {
  static final _kafka = KafkaRestService();
  static bool _initialized = false;

  /// Kafka REST Proxy 초기화
  static Future<void> init(String userId) async {
    if (!_initialized) {
      try {
        await _kafka.init(userId);
        _initialized = true;
        print('✅ ChatApi 초기화 완료');
      } catch (e) {
        print('❌ ChatApi 초기화 실패: $e');
        _initialized = false;
        rethrow;
      }
    }
  }

  /// Kafka를 통한 질문 전송
  static Future<Map<String, dynamic>> sendQuestion(String question) async {
    if (!_kafka.isConnected) {
      throw Exception('Kafka 연결 필요');
    }

    final completer = Completer<Map<String, dynamic>>();

    try {
      // 질문 전송
      final messageId = await _kafka.sendQuestion(question);
      print('📤 질문 전송: $messageId');

      // 답변 콜백 등록
      _kafka.registerCallback(messageId, (response) {
        if (!completer.isCompleted) {
          final result = {
            "text":
                response["answer"] ??
                response["text"] ??
                response["response"] ??
                "",
            "duration":
                ((response["processing_time_ms"] ?? 0) / 1000.0) as double,
            "lang": response["lang"] ?? "ko",
          };

          print('✅ 답변 처리 완료: $messageId');
          completer.complete(result);
        }
      });

      // 타임아웃 (30초)
      Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          print('⏱️ 타임아웃: $messageId');
          completer.complete({
            "text": "⏱️ 응답 시간 초과 (30초). 네트워크를 확인하고 다시 시도해주세요.",
            "duration": 0.0,
            "lang": "ko",
          });
        }
      });

      return completer.future;
    } catch (e) {
      print('❌ sendQuestion 에러: $e');
      return {
        "text": "❌ 전송 실패: ${e.toString()}",
        "duration": 0.0,
        "lang": "ko",
      };
    }
  }

  /// 개발용 Fake API (기존 유지)
  static Future<Map<String, dynamic>> fakeSttApi(String userMessage) async {
    await Future.delayed(const Duration(seconds: 2));
    return {
      "text":
          "거실에 불이 났다면 즉시 **안전을 우선**으로 생각하세요.\n"
          "1. **구조를 위해 즉시 대피**하세요.\n"
          "2. **소화기**나 **화재 대응 방법**을 활용해 초기 진화를 시도할 수 있지만, **안전이 우선**입니다.\n"
          "3. **소방서(119)**에 신고하세요.",
      "duration": 2.0,
      "lang": "ko",
    };
  }

  /// 리소스 정리
  static Future<void> dispose() async {
    await _kafka.dispose();
    _initialized = false;
  }
}
