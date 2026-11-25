"""Local preference suggestions and retrieval. No external API or extra model calls."""
import re
import threading
import time

# Deliberately conservative: only low-stakes, explicit first-person preference statements.
_PREFERENCE = re.compile(r"^我(?:平时|通常)?(?:很|比较|最)?(?:喜欢|不喜欢|爱)(?:吃|喝|听|看|读|阅读|打|玩|做|穿)(.{1,35})[。！!]*$")
_EXCLUDED = re.compile(r"密码|口令|令牌|密钥|账号|帐号|证件|身份证|地址|电话|银行卡|信用卡|病|药|性|政治|宗教|工资|收入|诊断|过敏|什么|如何|为什么|是不是|吗|呢|[0-9@:/\\?？]", re.I)

def preference_candidate(text):
    text = text.strip()
    if len(text) > 60 or not _PREFERENCE.fullmatch(text) or _EXCLUDED.search(text):
        return None
    return text.rstrip("。！!")

class PendingMemory:
    """A single transient proposal for a single-user service; never written to disk."""
    def __init__(self, ttl=300):
        self.ttl = ttl
        self._lock = threading.Lock()
        self._value = None
        self._expires = 0

    def offer(self, fact):
        with self._lock:
            self._value = fact
            self._expires = time.monotonic() + self.ttl

    def take(self):
        with self._lock:
            result = self._value if time.monotonic() < self._expires else None
            self._value = None
            self._expires = 0
            return result

    def clear(self):
        with self._lock:
            self._value = None
            self._expires = 0

_STOP = {"什么", "怎么", "如何", "请问", "告诉", "一下", "这个", "那个", "可以", "是否", "知道", "记得", "记忆", "我的", "你的", "我们", "你们", "一下"}

def relevant_memories(question, candidates, limit=4):
    """Prefer meaningful exact words and overlapping Chinese character pairs."""
    terms = set()
    for word in re.findall(r"[a-zA-Z0-9]{3,}|[\u4e00-\u9fff]{2,}", question.lower()):
        if re.fullmatch(r"[\u4e00-\u9fff]+", word):
            terms.update(word[i:i+2] for i in range(len(word)-1))
            if 3 <= len(word) <= 20:
                terms.add(word)
        else:
            terms.add(word)
    terms -= _STOP
    wants_preferences = any(word in question for word in ("我的喜好", "我的爱好", "我的偏好"))
    ranked = []
    seen = set()
    for recency, fact in enumerate(candidates):
        if fact in seen:
            continue
        seen.add(fact)
        normalized = fact.lower()
        score = sum(min(12, len(term)**2) for term in terms if term in normalized)
        if wants_preferences and preference_candidate(fact):
            score += 4
        if score:
            ranked.append((-score, recency, fact[:500]))
    ranked.sort()
    return [row[2] for row in ranked[:limit]]
