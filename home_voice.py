"""Render concise, natural speech for Siri without extra model requests."""
import re

REPEAT = {"再说一遍", "重复一遍", "重复刚才的回答", "刚才你说什么", "你刚才说什么", "刚才说什么", "没听清", "我没听清"}
FULL_REPEAT = {"完整重播", "完整朗读上一条", "把上一条完整读出来", "完整读一遍"}
DETAIL = {"详细一点", "再详细一点", "展开讲讲", "深入解释", "详细解释一下", "继续深入", "说具体一点", "展开说说", "详细解释"}
BRIEF = {"简单点", "简单说", "简短一点", "总结一下", "只说重点", "说重点"}
END = {"结束聊天", "结束这次对话", "今天聊到这里", "先聊到这里", "不聊了", "下次再聊"}
NEW = {"换个话题", "开始新话题", "开始新的对话", "重新开始对话"}
def command(text):
    text = text.strip().rstrip("。！？!? ")
    return "full_repeat" if text in FULL_REPEAT else "repeat" if text in REPEAT else "end" if text in END else "new" if text in NEW else None

def depth(text):
    text = text.strip().rstrip("。！？!? ")
    if text in DETAIL or text.startswith(("详细解释", "详细分析", "深入分析", "深入讲讲", "详细说说")):
        return "detail"
    if text in BRIEF or text.startswith(("简短回答", "一句话回答", "简单总结")):
        return "brief"
    return "normal"

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
    prefix = speech[:boundary+1].rstrip("，、, ")
    if not prefix.endswith(("。", "！", "？", "；", ".", "!", "?")):
        prefix += "。"
    return prefix + "如果你想听详细内容，可以继续问我。"
