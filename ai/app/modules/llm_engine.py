import os
import sys
from typing import List, Optional
from contextlib import AsyncExitStack

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_ollama import ChatOllama
from langchain_core.messages import SystemMessage, HumanMessage, ToolMessage, AIMessage
from config import logger

class LLMEngine:
    def __init__(self):
        self.session = Optional[ClientSession] = None
        self.exit_stack = AsyncExitStack()
        self.tool_definitions = []
        self.mcp_server_script = "mcp_server.py"
        
    async def connect_mcp(self):
        """MCP 서버 스크립트를 서브 프로세스로 실행하여 연결"""
        logger.info(f"MCP Server Process Connecting...")

        command = sys.executable
        script_path = os.path.abspath(self.mcp_server_script)

        server_params = StdioServerParameters(
            command = command,
            args=[script_path],
            env = os.environ.copy()
        )

        try:
            stdio_transport = await self.exit_stack.enter_async_context(stdio_client(server_params))
            self.session = await self.exit_stack.enter_async_context(
                ClientSession(stdio_transport[0], stdio_transport[1])
            )
            await self.session.initialize()

            response = await self.session.list_tools()
            self.tool_definitions = [
                {
                    "name" : tool.name,
                    "description" : tool.description,
                    "parameters" : tool.inputSchema
                }
                for tool in response.tools
            ]
            logger.info(f"LLM Engine 준비 완료 (Tools: {len(self.tool_definitions)}개)")
            return True
        except Exception as e:
            logger.error(f"MCP server Connect Fail: {e}")
            return False
    
    async def process_text(self, user_text: str) -> str:
        if not self.session:
            return "시스템 오류: MCP 연결이 되어있지 않습니다."

        llm = ChatOllama(
            model='gpt-oss:20b',
            temperature=0.1,
            num_ctx=4096
        )

        llm_with_tools = llm.bind_tools(self.tool_definitions)

        system_prompt = """당신은 스마트홈 AI입니다.
        1. 사용자가 "어둡다", "켜줘"라고 하면 관련 기기를 찾으세요.
        2. `find_entity_by_name`으로 기기를 검색합니다.
        3. [매우 중요] 검색 결과에 전등/스위치가 여러 개 나오면, 절대 하나씩 켜지 마세요.
        4. **반드시 `turn_on_multiple` 도구를 사용하여 발견된 모든 기기 ID를 리스트로 한 번에 전달하세요.**
        5. 답변에는 이모지(😊, ✅ 등)를 절대 포함하지 마세요.        
        """

        messages = [
            SystemMessage(content=system_prompt),
            HumanMessage(content=user_text)
        ]

        logger.info(f"Thinking: {user_text}")
        final_answer = ""

        # ReAct 루프
        for _ in range(10):
            response = await llm_with_tools.ainvoke(messages)
            messages.append(response)

            if not response.tool_calls:
                final_answer = response.content
                break
            
            for tool_call in response.tool_calls:
                t_name = tool_call["name"]
                t_args = tool_call["args"]
                t_id = tool_call["id"]

                logger.info(f"Tool Call: {t_name} {t_args}")

                try:
                    result = await self.session.call_tool(t_name, t_args)
                    result_text = result.content[0].text if result.content else str(result)
                except Exception as e:
                    result_text = f"Tool Error: {str(e)}"

                logger.info(f"Tool Result: {result_text}")
                messages.append(ToolMessage(content=result_text, tool_call_id =t_id))

        return final_answer if final_answer else "완료했습니다."

    async def cleanup(self):
        await self.exit_stack.aclose()