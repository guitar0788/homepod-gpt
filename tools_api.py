import xml.etree.ElementTree as ET
import html
import re

import httpx

def get(url, **params):
    with httpx.stream("GET", url, params=params, timeout=5) as response:
        response.raise_for_status()
        data = bytearray()
        for chunk in response.iter_bytes():
            data.extend(chunk)
            if len(data) > 512_000:
                raise ValueError("Response too large")
        return bytes(data)

def lookup(tool, query):
    if tool == "weather":
        import json
        locations = json.loads(get("https://geocoding-api.open-meteo.com/v1/search",
                                   name=query, count=1, language="zh")).get("results", [])
        if not locations:
            return "找不到这个城市。"
        place = locations[0]
        result = json.loads(get("https://api.open-meteo.com/v1/forecast",
                                latitude=place["latitude"], longitude=place["longitude"],
                                current="temperature_2m,relative_humidity_2m",
                                timezone="auto"))["current"]
        return (f'{place["name"]}，当地时间 {result["time"]}，'
                f'气温 {result["temperature_2m"]} 摄氏度，'
                f'相对湿度百分之 {result["relative_humidity_2m"]}。来源 Open-Meteo。')
    if tool == "news":
        items = ET.fromstring(get("https://news.google.com/rss/search",
                                  q=query, hl="zh-TW", gl="TW", ceid="TW:zh-Hant"))
        return [{"title": item.findtext("title", ""), "url": item.findtext("link", ""),
                 "published": item.findtext("pubDate", "")}
                for item in items.findall("./channel/item")[:5]]
    if tool == "search":
        import json
        data = json.loads(get("https://zh.wikipedia.org/w/api.php", action="query",
                              list="search", srsearch=query, srlimit=5, format="json"))
        return [{"title": item["title"], "url": f'https://zh.wikipedia.org/?curid={item["pageid"]}',
                 "snippet": html.unescape(re.sub(r"<[^>]*>", "", item.get("snippet", "")))[:350]}
                for item in data["query"]["search"]]
    raise ValueError("Unknown tool")
