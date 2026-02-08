import re

def remove_emojis(text: str) -> str:
    """텍스트에서 이모지와 특수 심볼을 제거합니다."""
    if not text:
        return ""
    
    emoji_pattern = re.compile("["
        u"\U00010000-\U0010FFFF"
        u"\u2700-\u27BF"
        u"\u2600-\u26FF"
        u"\u2300-\u23FF"
        "]+", flags=re.UNICODE)

    return emoji_pattern.sub(r'', text)
    