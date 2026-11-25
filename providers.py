import os

import httpx

ENDPOINTS = {
    "groq": "https://api.groq.com/openai/v1/chat/completions",
    "gemini": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    "openrouter": "https://openrouter.ai/api/v1/chat/completions",
    "openai": "https://api.openai.com/v1/chat/completions",
    "deepseek": "https://api.deepseek.com/v1/chat/completions",
}

def free_model(name, model):
    if name == "openrouter":
        return model == "openrouter/free" or model.endswith(":free")
    if name in {"groq", "gemini"}:
        # Operator must verify project billing is disabled and the specific model is free.
        return model in os.getenv(name.upper() + "_VERIFIED_FREE_MODELS", "").split(",")
    return False

def configured():
    result = {}
    for name in ENDPOINTS:
        prefix = name.upper()
        key = os.getenv(prefix + "_KEY")
        model = os.getenv(prefix + "_MODEL", "")
        if key and model and os.getenv(prefix + "_ENABLED") == "1":
            result[name] = model
    return result

def complete(name, model, messages):
    payload = {"model": model, "messages": messages, "max_tokens": 420}
    if name == "openrouter":
        payload["provider"] = {"allow_fallbacks": False, "data_collection": "deny",
                               "max_price": {"prompt": 0, "completion": 0}}
    response = httpx.post(ENDPOINTS[name], json=payload, timeout=7,
                          headers={"Authorization": "Bearer " + os.environ[name.upper() + "_KEY"]})
    response.raise_for_status()
    answer = response.json()["choices"][0]["message"]["content"]
    if not isinstance(answer, str) or not answer.strip():
        raise ValueError("Empty answer")
    return answer.strip()
