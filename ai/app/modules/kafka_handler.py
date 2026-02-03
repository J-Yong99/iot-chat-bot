import json
from datetime import datetime
from typing import Dict, Any
from confluent_kafka import Consumer, Producer, KafkaError
from config import KAFKA_BOOTSTRAP, TOPIC_REQUEST, TOPIC_RESPONSE, GROUP_ID, logger

class KafkaHandler:
    def __init__(self):
        self.producer = Producer({
            'bootstrap.servers' : KAFKA_BOOTSTRAP,
            'client.id' : 'ha-agent-producer',
            'message.max.bytes' : 10000000
        })

        self.consumer = Consumer({
            'bootstrap.servers': KAFKA_BOOTSTRAP,
            'group.id': GROUP_ID,
            'auto.offset.reset': 'latest'
        })
        self.consumer.subscribe([TOPIC_REQUEST])

    def send_response(self, original_msg: Dict, answer: str, processing_time: float):
        """응답을 Kafka로 전송합니다."""
        origin_meta = original_msg.get("metadata", {})
        origin_meta['processing_time_ms'] = processing_time

        # 이모지 제거 및 정제
        clean_answer = remove_emojis(answer)

        payload = {
            "message_id": original_msg.get("message_id"),
            "user_id": original_msg.get("user_id"),
            "answer": clean_answer,
            "metadata": origin_meta
        }

        try:
            self.producer.produce(
                TOPIC_RESPONSE,
                json.dumps(payload, ensure_ascii= False).encode('utf-8')
            )
            self.producer.flush()
            logger.info(f" Kafka 전송 완료: {clean_answer[:30]}...")
        except Exception as e:
            logger.error(f"Kafka 전송 실패: {e}")
    
    def close(self):
        self.consumer.close()