from typing import List
from mcp.server.fastmcp import FastMCP
from ha_api import HomeAssistantAPI
from config import HA_URL, HA_TOKEN

mcp = FastMCP("homeassistant")
hass_api = HomeAssistantAPI(HA_URL, HA_TOKEN) if HA_URL and HA_TOKEN else None

@mcp.tool()
async def find_entity_by_name(search_term: str) -> str:
    """기기 이름이나 장소를 검색하여 ID 목록을 반환합니다. (예: '거실', '전등')"""
    if not hass_api: return "Error: HA API not connected"
    try:
        states = await hass_api.make_request("GET", "states")
        search_lower = search_term.lower().replace(" ", "")
        matches = []

        for state in states:
            entity_id = state.get("entity_id", "")
            friendly = state.get("attributes", {}).get("friendly_name", "").lower().replace(" ","")
            state_val = state.get("state")

            domain = entity_id.split('.')[0]
            if domain not in ["light", "switch", "media_player", "climate", "fan", "cover"]:
                continue
            
            if search_lower in friendly or search_lower in entity_id.lower():
                matches.append(f"- ID: {entity_id} (이름: {state.get('attributes', {}).get('friendly_name')}, 상태: {state_val})")
            
        if not matches:
            return "검색 결과가 없습니다."
        return "\n".join(matches[:15])
    except Exception as e:
        return f"Error: {str(e)}"

@mcp.tool()
async def turn_on_multiple(entity_ids: List[str]) -> str:
    """여러 기기를 한 번에 켭니다. 입력값은 entity_id들의 리스트여야 합니다."""
    if not hass_api: return "Error: HA API not connected"
    results = []
    for eid in entity_ids:
        try:
            await hass_api.make_request("POST","services/homeassistant/turn_on", {"entity_id": eid})
            results.append(f"success: {eid} on")
        except Exception as e:
            results.append(f"fail: {eid} error: {e}")
    return "\n".join(results)

@mcp.tool()
async def turn_off_multiple(entity_ids: List[str]) -> str:
    """여러 기기를 한 번에 끕니다. 입력값은 entity_id들의 리스트여야 합니다."""
    if not hass_api: return "Error: HA API not connected"
    results = []
    for eid in entity_ids:
        try:
            await hass_api.make_request("POST","services/homeassistant/turn_off", {"entity_id": eid})
            results.append(f"success: {eid} off")
        except Exception as e:
            results.append(f"fail: {eid} error: {e}")
    return "\n".join(results)

if __name__ == "__main__":
    # 이 파일이 직접 실행될 때만 MCP 서버 가동
    mcp.run()