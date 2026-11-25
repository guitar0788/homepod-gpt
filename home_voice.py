"""Render concise, natural speech for Siri without extra model requests."""
import re

REPEAT = {"再说一遍", "重复一遍", "重复刚才的回答", "刚才你说什么", "你刚才说什么", "刚才说什么", "没听清", "我没听清"}
END = {"结束聊天", "结束这次对话", "今天聊到这里", "先聊到这里", "不聊了", "下次再聊"}
NEW = {"换个话题", "开始新话题", "开始新的对话", "重新开始对话"}
def command(text):
    text = text.strip().rstrip("。！？!? ")
    return "repeat" if text in REPEAT else "end" if text in END else "new" if text in NEW else None

def clean(text):
    text = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\(https?://[^)]+\)", r"\1", text)
    text = re.sub(r"https?://[^\s，。！？]+", "", text)
    text = re.sub(r"(?m)^\s*[-*#>]+\s*", "", text)
    text = re.sub(r"(?m)^\s*\d+[.)、]\s*", "", text)
    text = re.sub(r"[*_\x60#]", "", text)
    return re.sub(r"\s+", " ", text).strip()

def render(answer, maximum=300):
    speech = clean(answer)
    if len(speech) <= maximum:
        return speech
    boundary = max(speech.rfind(c, 0, maximum) for c in "。！？；.!?")
    if boundary < maximum // 2:
        boundary = max(speech.rfind(c, 0, maximum) for c in "，、, ")
    if boundary < maximum // 2:
        boundary = maximum-1
    return speech[:boundary+1].rstrip("，、, ") + "。如果你想听详细内容，可以继续问我。"
