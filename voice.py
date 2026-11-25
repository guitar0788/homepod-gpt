"""Speech formatting and bounded response policy for the HomePod voice interface."""
import re

STYLE = """这是家庭音箱上的中文语音对话，不是书面报告。直接回答，不复述问题，
不要念网址、Markdown、表格、括号堆叠或长串编号。使用自然的完整句子，默认约60至120字。
复杂解释先给结论和关键原因；用户明确要求详细时可多说一些。结合获准使用的历史理解省略和追问，
不要每次自我介绍，不必强行以问题结束。用户未提供的事实不要猜测。不能实际控制音箱麦克风、
保持监听或执行设备动作，不得声称已执行。遇到需要最新资料的问题才提出研究。"""

_REPEAT = {"再说一遍", "再说一次", "重复一下", "刚才没听清", "刚才没听清楚",
           "你刚才说什么", "你刚才说了什么", "刚才说的再说一遍", "能再说一遍吗"}
_END = {"结束聊天", "结束对话", "先聊到这里", "今天先聊到这里"}

def local_action(text):
    text = re.sub(r"[。！!？?，,\s]+$", "", text.strip())
    if text in _REPEAT:
        return "repeat"
    if text in _END:
        return "end"
    return None

def render(text, maximum=350):
    # Preserve link labels and prose, but avoid reading URLs and formatting punctuation.
    text = re.sub(r"\[([^\]\n]+)\]\(https?://[^)\s]+\)", r"\1", text)
    text = re.sub(r"https?://[^\s，。！？；、]+", "", text)
    text = re.sub(r"(?m)^\s*(?:[-*+]\s+|#{1,6}\s+)", "", text)
    text = re.sub(r"[\x60*_#]", "", text)
    text = re.sub(r"\s*\|\s*", "，", text)
    text = re.sub(r"\s*\n+\s*", "。", text)
    text = re.sub(r"。{2,}", "。", text).strip()
    if len(text) <= maximum:
        return text or "暂时没有可朗读的内容。"
    # Prefer a full sentence, and never claim the iPhone app displays a transcript.
    suffix = "。你可以接着问我具体细节。"
    room = maximum - len(suffix)
    head = text[:room]
    end = max(head.rfind(p) for p in "。！？；!?")
    if end >= int(room * .65):
        head = head[:end]
    return head.rstrip("，。！？；、 ") + suffix

# HTTPX timeouts apply to individual phases, not a hard end-to-end deadline.
# Only start a second attempt when there is reasonable remaining time.
FIRST_TIMEOUT = 12.0
TOTAL_TARGET = 24.0
MIN_REMAINING = 5.0

def timeout_for(elapsed):
    remaining = TOTAL_TARGET - elapsed
    return min(FIRST_TIMEOUT, remaining) if remaining >= MIN_REMAINING else None
