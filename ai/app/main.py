import json
import asyncio
import logging
from datetime import datetime
from confluent_kafka import KafkaError

from config import logger, KAFKA_BOOTSTRAP
from modules.kafka_handler import KafkaHandler
from modules.llm_engine import LLMEngine

async def main():
    # 1. 모듈 초기화
    kafka = KafkaHandler()
    llm_engine = LLMEngine()

    # 2. MCP 서버(Tool) 연결
    if not await llm_engine.connect_mcp():
        logger.error("프로그램을 종료합니다.")
        return

    logger.info(f"Kafka Consumer 시작 {KAFKA_BOOTSTRAP}")

    try:
        while True:
            msg = kafka.consumer.poll(0.5)

            if msg is None:
                await asyncio.sleep(0.1)
                continue

            if msg.error():
                if msg.error().code() != KafkaError._PARTITION_EOF:
                    logger.error(f"Kafka Error: {msg.error()}")
                continue

            try:
                start_time = datetime.now()
                data = json.loads(msg.value().decode('utf-8'))

                user_text = data.get("text") or data.get("question")
                logger.info(f"요청 수신 : {user_text}")