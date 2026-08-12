#!/usr/bin/env python3
"""Весы QN-Scale (Libra CS20C1): рукопожатие и расшифровка веса.

Протокол (сервис fff0): notify fff1, запись fff2.
Кадр: [тип][длина][...полезная нагрузка...][контрольная сумма = сумма предыдущих % 256]
  0x12 — весы представляются (MAC и т.п.), ждут ответа
  0x13 — наш ответ: «работаем в кг»
  0x10 — измерение

Запуск:  open -n -a BLEScan.app --args <путь>/connect.py [секунд]
Лог: connect_out.txt
"""
import asyncio, os, sys, time
from datetime import datetime

from bleak import BleakScanner, BleakClient

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = open(os.path.join(HERE, "connect_out.txt"), "w", buffering=1)

TARGET_NAME = "QN-Scale"
CH_NOTIFY = "0000fff1-0000-1000-8000-00805f9b34fb"
CH_WRITE = "0000fff2-0000-1000-8000-00805f9b34fb"

t0 = time.time()
client_ref = None
handshaked = 0.0


def say(msg):
    print(msg, flush=True)
    OUT.write(msg + "\n")


def frame(payload: bytes) -> bytes:
    """Дописывает контрольную сумму (сумма байтов % 256)."""
    return payload + bytes([sum(payload) & 0xFF])


# «Работаем в килограммах» — 13 09 15 01 10 00 00 00 + сумма (0x42)
HELLO_KG = frame(bytes([0x13, 0x09, 0x15, 0x01, 0x10, 0x00, 0x00, 0x00]))


def decode(d: bytes) -> str:
    ok = (sum(d[:-1]) & 0xFF) == d[-1]
    mark = "" if ok else "  [!сумма не сошлась]"
    if d[0] == 0x12:
        mac = ":".join(f"{x:02x}" for x in d[3:9][::-1])
        return f"  ==> представление весов, MAC {mac}{mark}"
    if d[0] == 0x10 and len(d) >= 6:
        w_be = ((d[3] << 8) | d[4]) / 100.0
        w_le = ((d[4] << 8) | d[3]) / 100.0
        return f"  ==> измерение: BE={w_be:.2f} кг / LE={w_le:.2f} кг, байт5={d[5]:#04x}{mark}"
    return f"  ==> тип {d[0]:#04x}{mark}"


async def send(data: bytes, why: str):
    for with_response in (True, False):
        try:
            await client_ref.write_gatt_char(CH_WRITE, data, response=with_response)
            say(f"          → в fff2: {data.hex(' ')}   ({why}, response={with_response})")
            return
        except Exception as e:
            say(f"          ! запись response={with_response} не прошла: {e}")


def notif(sender, data: bytearray):
    global handshaked
    b = bytes(data)
    say(f"[{time.time() - t0:7.2f}s] NOTIFY {sender.uuid[4:8]} len={len(b):2}  {b.hex(' ')}{decode(b)}")
    # весы повторяют «привет», пока не получат корректный ответ — отвечаем не чаще раза в секунду
    if b[0] == 0x12 and time.time() - handshaked > 1.0:
        handshaked = time.time()
        asyncio.create_task(send(HELLO_KG, "рукопожатие: килограммы"))


async def session(dev, listen):
    global client_ref
    async with BleakClient(dev) as client:
        client_ref = client
        say(f"Подключился ({datetime.now():%H:%M:%S})")
        for svc in client.services:
            for ch in svc.characteristics:
                if "notify" in ch.properties or "indicate" in ch.properties:
                    await client.start_notify(ch, notif)
                    say(f"  подписался на {ch.uuid[4:8]}")
        say(f"--- слушаю {listen:.0f} c ---")
        end = time.time() + listen
        while time.time() < end and client.is_connected:
            await asyncio.sleep(0.5)
        say("Соединение закрыто" if not client.is_connected else "Время вышло")


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-psn")]
    listen = float(args[0]) if args else 150
    say(f"Ищу {TARGET_NAME}… ({datetime.now():%H:%M:%S})")
    deadline = time.time() + 300
    while time.time() < deadline:
        dev = await BleakScanner.find_device_by_filter(
            lambda d, adv: (adv.local_name or d.name or "") == TARGET_NAME, timeout=60)
        if dev is None:
            say("…не вижу весы, ищу дальше")
            continue
        say(f"Нашёл: {dev.address}")
        try:
            await session(dev, listen)
            return
        except Exception as e:
            say(f"Ошибка сессии: {e!r} — пробую снова")
    say("Время поиска вышло.")


asyncio.run(main())
