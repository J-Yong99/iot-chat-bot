// lib/core/api/chat_api.dart
import 'dart:async';
import '../services/kafka_rest_service.dart';
import 'dart:convert'; // jsonDecode, utf8.decode 사용
import 'dart:io'; // File 객체 사용
import 'package:http/http.dart' as http; // HTTP 통신 사용

class ChatApi {
  static final _kafka = KafkaRestService();
  static bool _initialized = false;
  static const String _sttUrl = 'http://hansolsong.iptime.org:8787/transcribe';

  /// Kafka REST Proxy 초기화
  static Future<void> init(String userId) async {
    try {
      // 항상 새로 초기화되도록 강제
      await _kafka.dispose();

      await _kafka.init(userId);
      _initialized = true;
      print('✅ ChatApi 초기화 완료 (강제 재초기화)');
    } catch (e) {
      print('❌ ChatApi 초기화 실패: $e');
      _initialized = false;
      rethrow;
    }
  }

  // ➡️ [NEW] 음성 파일을 STT 서버로 전송하고 텍스트를 반환하는 함수
  static Future<String> transcribeVoice(String audioFilePath) async {
    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found at path: $audioFilePath');
    }

    print('📤 STT 서버로 파일 전송 시작: $_sttUrl');

    try {
      // 1. Multipart Request 생성
      var request = http.MultipartRequest('POST', Uri.parse(_sttUrl));

      // 2. 'file' 필드에 오디오 파일 추가
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // 서버에서 요구하는 필드명
          audioFilePath,
        ),
      );

      // 3. 요청 전송 및 응답 처리
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        print('✅ STT Response (200 OK): $jsonResponse');

        // 서버 응답에서 'text' 키를 찾아 변환된 텍스트 반환을 가정
        if (jsonResponse.containsKey("text") &&
            jsonResponse["text"] is String) {
          return jsonResponse["text"];
        }

        // STT 서버가 텍스트 없이 응답만 보내는 경우의 예외 처리
        return "STT 처리 완료. 하지만 서버에서 변환된 텍스트를 받지 못했습니다.";
      } else {
        // 서버 응답 오류 처리
        print('❌ STT 요청 실패 (${response.statusCode}): ${response.body}');
        return 'STT 요청 실패: 서버 응답 ${response.statusCode}';
      }
    } catch (e) {
      print('❌ STT 전송 중 예외 발생: $e');
      return 'STT 전송 실패: ${e.toString()}';
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
                ((response["metadata"]?["processing_time_ms"] ?? 0) / 1000.0)
                    as double,
            "lang": response["metadata"]?["language"] ?? "ko",
          };

          print('✅ 답변 처리 완료: $messageId');
          completer.complete(result);
        }
      });

      // 타임아웃 (30초)
      Timer(const Duration(seconds: 300), () {
        if (!completer.isCompleted) {
          print('⏱️ 타임아웃: $messageId');
          completer.complete({
            "text": "⏱️ 응답 시간 초과 (30초). 네트워크를 확인하고 다시 시도해주세요.",
            "duration": 30.0,
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
