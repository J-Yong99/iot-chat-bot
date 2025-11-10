// // lib/test/kafka_connection_test.dart
// import 'package:fkafka/fkafka.dart';
//
// Future<void> testKafkaConnection() async {
//   print('🧪 Kafka 연결 테스트 시작...');
//
//   try {
//     // 설정
//     final config = KafkaConfig(
//       bootstrapServers: ['118.36.36.206:9092'],
//     );
//
//     print('📡 Kafka 연결 시도...');
//
//     // Producer 테스트
//     final producer = KafkaProducer(config);
//     await producer.connect();
//
//     print('✅ Producer 연결 성공!');
//
//     // 테스트 메시지 전송
//     await producer.send(
//       topic: 'chat-requests',
//       key: 'test-user',
//       value: '{"message_id": "test-001", "question": "테스트"}',
//     );
//
//     print('✅ 메시지 전송 성공!');
//
//     await producer.disconnect();
//     print('✅ 연결 테스트 완료!');
//
//   } catch (e) {
//     print('❌ 연결 실패: $e');
//     print('ℹ️  에러 타입: ${e.runtimeType}');
//   }
// }