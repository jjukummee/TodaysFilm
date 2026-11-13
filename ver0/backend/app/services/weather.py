"""날씨 조회 (3차: 위치/날씨 기반 회고 보조).

Open-Meteo 무료 API 사용 — API 키 불필요.
실패해도 회고 플로우를 막지 않도록 항상 fail-soft (None 반환).
"""
import json
import urllib.parse
import urllib.request

from ..config import get_settings

# WMO weather code → 한국어 요약
_CODE_MAP = {
    0: "맑음", 1: "대체로 맑음", 2: "구름 조금", 3: "흐림",
    45: "안개", 48: "안개",
    51: "이슬비", 53: "이슬비", 55: "이슬비",
    61: "비", 63: "비", 65: "강한 비", 66: "비", 67: "비",
    71: "눈", 73: "눈", 75: "많은 눈", 77: "눈",
    80: "소나기", 81: "소나기", 82: "강한 소나기",
    95: "뇌우", 96: "뇌우", 99: "뇌우",
}


def get_weather_summary(latitude: float, longitude: float) -> str | None:
    """예: '맑음, 27°C'. 조회 실패 시 None."""
    settings = get_settings()
    if not settings.weather_enabled:
        return None

    params = urllib.parse.urlencode({
        "latitude": round(latitude, 4),
        "longitude": round(longitude, 4),
        "current": "temperature_2m,weather_code",
        "timezone": "Asia/Seoul",
    })
    url = f"https://api.open-meteo.com/v1/forecast?{params}"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read())
        current = data.get("current", {})
        code = current.get("weather_code")
        temp = current.get("temperature_2m")
        desc = _CODE_MAP.get(code, "")
        if temp is None and not desc:
            return None
        parts = [p for p in (desc, f"{round(temp)}°C" if temp is not None else None) if p]
        return ", ".join(parts)
    except Exception:
        return None  # 날씨는 부가 정보 — 실패가 회고를 막으면 안 됨
