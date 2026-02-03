import os
import sys
import logging
from dotenv import load_dotenv

load_dotenv()

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP")
TOPIC_REQUEST = os.getenv("TOPIC_REQUEST")
TOPIC_RESPONSE = os.getenv("TOPIC_RESPONSE")
GROUP_ID = os.getenv("GROUP_ID")

HA_URL = os.getenv("HA_URL")
HA_TOKEN = os.getenv("HA_TOKEN")

def setup_logger(name="HA-AGENT"):
    logging.basicConfig(
        level=logging.INFO,
        format='[%(name)s] %(message)s',
        stream=sys.stderr
    )
    return logging.getLogger(name)

logger = setup_logger()