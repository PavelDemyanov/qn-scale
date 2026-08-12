#!/usr/bin/env python3
"""Сниффер BLE-рекламы: ищем весы и смотрим, что они вещают.

Пишет всё в scan_log.jsonl, а «интересное» — в scan_out.txt и на экран:
новые устройства и изменения полезной нагрузки (без спама Apple/Microsoft).
"""
import asyncio, json, os, sys, time
from datetime import datetime

from bleak import BleakScanner

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = open(os.path.join(HERE, "scan_log.jsonl"), "a", buffering=1)
OUT = open(os.path.join(HERE, "scan_out.txt"), "w", buffering=1)

# Производители, чьи маячки меняются постоянно и нам не интересны
NOISY_MFR = {0x004C, 0x0006, 0x0075, 0x00E0}

NAME_HINTS = ("scale", "cs20", "libra", "feelfit", "chipsea", "okok", "qn-",
              "weight", "body", "fat", "health", "yolanda", "senssun", "icomon")
UUID_HINTS = ("0000181d", "0000181b", "0000fff0", "0000ffb0", "0000fee0",
              "0000ffe0", "000018f0", "0000fff1")

seen: dict[str, dict] = {}
t0 = time.time()


def say(msg):
    print(msg, flush=True)
    OUT.write(msg + "\n")


def payload(adv) -> str:
    parts = []
    for cid, data in sorted(adv.manufacturer_data.items()):
        parts.append(f"MFR:{cid:04x}={data.hex()}")
    for uuid, data in sorted(adv.service_data.items()):
        parts.append(f"SVC:{uuid[4:8]}={data.hex()}")
    return " ".join(parts)


def interesting(dev, adv) -> bool:
    name = (adv.local_name or dev.name or "").lower()
    if any(h in name for h in NAME_HINTS):
        return True
    for u in list(adv.service_uuids) + list(adv.service_data):
        if any(u.lower().startswith(h) for h in UUID_HINTS):
            return True
    for cid in adv.manufacturer_data:
        if cid not in NOISY_MFR:
            return True
    return False


def cb(dev, adv):
    p = payload(adv)
    name = adv.local_name or dev.name or "—"
    key = dev.address
    rec = {"t": round(time.time() - t0, 2), "addr": key, "name": name,
           "rssi": adv.rssi, "payload": p, "uuids": list(adv.service_uuids)}
    LOG.write(json.dumps(rec, ensure_ascii=False) + "\n")

    prev = seen.get(key)
    seen[key] = rec
    if not interesting(dev, adv):
        return
    ts = datetime.now().strftime("%H:%M:%S")
    if prev is None:
        say(f"[{ts}] NEW  {name!r:24} {key}  rssi={adv.rssi:4}  {p}")
        if adv.service_uuids:
            say(f"                 services: {', '.join(adv.service_uuids)}")
    elif prev["payload"] != p and p:
        say(f"[{ts}] CHG  {name!r:24} {key}  rssi={adv.rssi:4}  {p}")


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-psn")]
    secs = float(args[0]) if args else 60
    try:
        from CoreBluetooth import CBCentralManager
        say(f"CoreBluetooth authorization = {CBCentralManager.authorization()} "
            f"(0=не определено, 2=запрещено, 3=разрешено)")
    except Exception as e:
        say(f"(не смог прочитать статус доступа: {e})")
    say(f"Сканирую {secs:.0f} c…")
    scanner = BleakScanner(detection_callback=cb)
    await scanner.start()
    await asyncio.sleep(secs)
    await scanner.stop()
    say(f"Готово. Всего устройств: {len(seen)}")


asyncio.run(main())
