import aiohttp
from typing import Optional, Dict, Any
from config import logger

class HomeAssistantAPI:
    def __init__(self, url: str, token: str):
        self.url = url.rstrip('/')
        self.token = token
        self.headers = {
            "Authorization" : f"Bearer {token}",
            "Content-Type" : "application/json"
        }

    async def make_request(self, method: str, endpoint: str, data: Optional[Dict] = None) -> Dict[str, Any]:
        url = f"{self.url}/api/{endpoint}"
        timeout = aiohttp.ClientTimeout(total=10)
        try:
            async with aiohttp.ClientSession(timeout=timeout) as session:
                if method.upper() == "GET":
                    async with session.get(url, headers=self.headers) as response:
                        response.raise_for_status()
                        return await response.json()
                elif method.upper() == "POST":
                    async with session.post(url, headers = self.headers, json=data) as response:
                        response.raise_for_status()
                        return await response.json()
        except Exception as e:
            logger.error(f"HA API Request Error: {e}")
            raise