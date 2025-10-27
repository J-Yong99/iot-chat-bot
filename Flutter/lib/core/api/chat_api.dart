import 'dart:async';

/// 실제 API 연결 시에는 http.post(...) 로 교체 가능.
/// 지금은 데모용으로 STT 결과를 흉내냅니다.
class ChatApi {
  static Future<Map<String, dynamic>> fakeSttApi(String userMessage) async {
    await Future.delayed(const Duration(seconds: 2));

    final Map<String, dynamic> fakeResponse = {
      "status": 200,
      "lang": "ko",
      "data": {
        "text":
            "거실에 불이 났다면 즉시 **안전을 우선**으로 생각하세요.\n"
            "1. **구조를 위해 즉시 대피**하세요.\n"
            "2. **소화기**나 **화재 대응 방법**을 활용해 초기 진화를 시도할 수 있지만, **안전이 우선**입니다.\n"
            "3. **소방서(119)**에 신고하세요.\n\n"
            "만약 **실제로 불이 났다**고 느낀다면, 위의 절차를 따라주세요.\n"
            "다른 의미로 해석 될 수 있다면 추가 설명해 주세요! 🔥",
        "duration": 6.78,
      },
    };

    return {
      "text": fakeResponse["data"]?["text"] ?? "",
      "duration": fakeResponse["data"]?["duration"] ?? 0.0,
      "lang": fakeResponse["lang"] ?? "unknown",
    };
  }
}
