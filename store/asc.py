#!/usr/bin/env python3
"""Клиент App Store Connect для витрины QN Scale.

Отдельный от tools/asc соседнего проекта: тот заточен под чтение статуса и
отправку, а здесь нужны произвольные запросы к API — метаданные, скриншоты,
TestFlight. Ошибки НЕ роняют процесс: возвращается пара (код, тело), потому что
половина вызовов тут разведочные и 404/409 — нормальный ответ.

Ключ и идентификаторы — в ~/.appstoreconnect/config.json (профиль euclogger:
именно у этого ключа есть права на облачную подпись и на запись метаданных).

Использование:
    python3 asc.py GET /v1/apps/6800921179
    python3 asc.py PATCH /v1/appInfos/XXX '{"data": ...}'
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.expanduser("~/Projects/csvEUC/tools/asc"))
import jwt  # noqa: E402  (из .venv соседнего проекта)

API = "https://api.appstoreconnect.apple.com"
CONFIG = os.path.expanduser("~/.appstoreconnect/config.json")
APP_ID = "6800921179"          # QN Scale, com.redpax.Libra


def config(profile: str = "euclogger") -> dict:
    cfg = json.load(open(CONFIG))
    return {**cfg, **cfg["profiles"][profile]}


def token() -> str:
    cfg = config()
    key = open(os.path.expanduser(cfg["p8"])).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": cfg["issuerId"], "iat": now, "exp": now + 19 * 60,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": cfg["keyId"], "typ": "JWT"})


def call(path: str, method: str = "GET", body=None, raw: bytes = None,
         content_type: str = "application/json", extra_headers: dict = None):
    """Возвращает (код, тело). Тело — словарь, или строка, если не JSON."""
    url = path if path.startswith("http") else API + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data is not None:
        req.add_header("Content-Type", content_type)
    for k, v in (extra_headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as r:
            payload = r.read()
            try:
                return r.status, (json.loads(payload) if payload else {})
            except json.JSONDecodeError:
                return r.status, payload
    except urllib.error.HTTPError as e:
        payload = e.read()
        try:
            return e.code, json.loads(payload)
        except Exception:
            return e.code, payload.decode(errors="replace")


def errors(body) -> str:
    if isinstance(body, dict) and body.get("errors"):
        return "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in body["errors"])
    return str(body)[:400]


if __name__ == "__main__":
    method = sys.argv[1].upper() if len(sys.argv) > 2 else "GET"
    path = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
    payload = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    st, data = call(path, method, payload)
    print(st)
    print(json.dumps(data, ensure_ascii=False, indent=2)[:6000])
