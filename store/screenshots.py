#!/usr/bin/env python3
"""Заливка скриншотов витрины.

Протокол Apple трёхшаговый: резервируем место (`POST /v1/appScreenshots`
возвращает список адресов), кладём БАЙТЫ по этим адресам кусками, подтверждаем
контрольной суммой. Без третьего шага картинка навсегда остаётся в состоянии
«загружается»: в витрине её не видно и версию отправить нельзя.

Набор — `APP_IPHONE_67`. Снимки у нас 1320×2868 (6,9″), но типа
`APP_IPHONE_69` API не знает: шестидюймовые с половиной и почти семь идут в
один набор.
"""

import hashlib
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402

DISPLAY = "APP_IPHONE_67"


def sets_of(localization_id: str) -> dict:
    st, d = asc.call(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    return {x["attributes"]["screenshotDisplayType"]: x["id"] for x in d.get("data", [])}


def create_set(localization_id: str) -> str:
    st, d = asc.call("/v1/appScreenshotSets", "POST", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})
    if st != 201:
        raise SystemExit(f"набор не создан: {asc.errors(d)}")
    return d["data"]["id"]


def upload(set_id: str, path: str) -> str:
    data = open(path, "rb").read()
    st, d = asc.call("/v1/appScreenshots", "POST", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {
            "data": {"type": "appScreenshotSets", "id": set_id}}}}})
    if st != 201:
        raise SystemExit(f"место не выделено ({os.path.basename(path)}): {asc.errors(d)}")
    shot = d["data"]["id"]
    for op in d["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req) as resp:
            resp.read()
    st, d = asc.call(f"/v1/appScreenshots/{shot}", "PATCH", {"data": {
        "type": "appScreenshots", "id": shot,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    if st != 200:
        raise SystemExit(f"не подтверждено: {asc.errors(d)}")
    return shot


def order(set_id: str, shot_ids: list) -> None:
    """Порядок в наборе задаётся ОТДЕЛЬНЫМ запросом: заливка идёт параллельно,
    и полагаться на порядок создания нельзя."""
    st, d = asc.call(f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots", "PATCH",
                     {"data": [{"type": "appScreenshots", "id": i} for i in shot_ids]})
    if st not in (200, 204):
        raise SystemExit(f"порядок не задан: {asc.errors(d)}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    plan = {
        "ru": ("b2db7ebb-05e1-4d73-b3a1-079acc5fb0da",
               ["ru-1-main.png", "ru-2-history.png", "ru-3-goal.png", "ru-4-settings.png"]),
        "en-US": ("d4025baf-d351-4782-b3e7-3d7eaa1ea064",
                  ["en-1-main.png", "en-2-history.png", "en-3-goal.png", "en-4-settings.png"]),
    }
    for locale, (loc_id, files) in plan.items():
        existing = sets_of(loc_id)
        set_id = existing.get(DISPLAY) or create_set(loc_id)
        ids = []
        for f in files:
            ids.append(upload(set_id, os.path.join(here, "screenshots", f)))
            print(f"  {locale}: {f}")
        order(set_id, ids)
        print(f"{locale}: {len(ids)} снимков в наборе {DISPLAY}")
