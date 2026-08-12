#!/usr/bin/env python3
"""Демон для весов QN-Scale (Libra CS20C1).

Логика: весы вещают только когда проснулись (на них наступили). Ждём свежую
рекламу → подключаемся → отвечаем на «привет» → слушаем. Если за 40 с не
пришло ни одного измерения — рвём соединение и ждём следующего пробуждения.

Запуск:  open -n -a BLEScan.app --args <путь>/watch.py [минут]
Лог: watch_out.txt
"""
import asyncio, os, sys, time
from datetime import datetime

from bleak import BleakScanner, BleakClient

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = open(os.path.join(HERE, "watch_out.txt"), "w", buffering=1)

TARGET_NAME = "QN-Scale"
CH_WRITE = "0000fff2-0000-1000-8000-00805f9b34fb"
IDLE_LIMIT = 40  # с без измерений → переподключение

t0 = time.time()


def say(msg):
    print(msg, flush=True)
    OUT.write(f"{msg}\n")


def frame(payload: bytes) -> bytes:
    return payload + bytes([sum(payload) & 0xFF])


HELLO_KG = frame(bytes([0x13, 0x09, 0x15, 0x01, 0x10, 0x00, 0x00, 0x00]))


class Session:
    def __init__(self, client):
        self.client = client
        self.last_data = time.time()
        self.last_hello = 0.0
        self.got_measurement = False

    def describe(self, d: bytes) -> str:
        ok = (sum(d[:-1]) & 0xFF) == d[-1]
        mark = "" if ok else "  [!сумма не сошлась]"
        if d[0] == 0x12:
            return f"  ==> «привет» от весов{mark}"
        if d[0] == 0x14:
            return f"  ==> подтверждение настроек{mark}"
        if d[0] == 0x10 and len(d) >= 6:
            be = ((d[3] << 8) | d[4]) / 100.0
            le = ((d[4] << 8) | d[3]) / 100.0
            return f"  ==> ИЗМЕРЕНИЕ: BE={be:.2f} кг / LE={le:.2f} кг, байт5={d[5]:#04x}{mark}"
        return f"  ==> тип {d[0]:#04x}{mark}"

    def on_notify(self, sender, data: bytearray):
        b = bytes(data)
        self.last_data = time.time()
        say(f"[{time.time() - t0:7.1f}s] {sender.uuid[4:8]} len={len(b):2}  {b.hex(' ')}{self.describe(b)}")
        if b[0] == 0x10:
            self.got_measurement = True
        if b[0] == 0x12 and time.time() - self.last_hello > 1.0:
            self.last_hello = time.time()
            asyncio.create_task(self.reply(HELLO_KG))

    async def reply(self, data: bytes):
        for resp in (True, False):
            try:
                await self.client.write_gatt_char(CH_WRITE, data, response=resp)
                say(f"           → в fff2: {data.hex(' ')}")
                return
            except Exception as e:
                say(f"           ! запись (response={resp}) не прошла: {e}")


async def one_cycle():
    dev = await BleakScanner.find_device_by_filter(
        lambda d, adv: (adv.local_name or d.name or "") == TARGET_NAME, timeout=30)
    if dev is None:
        return False
    say(f"— весы проснулись, подключаюсь ({datetime.now():%H:%M:%S})")
    async with BleakClient(dev) as client:
        s = Session(client)
        for svc in client.services:
            for ch in svc.characteristics:
                if "notify" in ch.properties or "indicate" in ch.properties:
                    await client.start_notify(ch, s.on_notify)
        while client.is_connected and time.time() - s.last_data < IDLE_LIMIT:
            await asyncio.sleep(0.3)
        say(f"— сессия закончена (измерения: {'да' if s.got_measurement else 'нет'})")
    return True


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-psn")]
    minutes = float(args[0]) if args else 10
    say(f"Демон запущен на {minutes:.0f} мин ({datetime.now():%H:%M:%S}). Наступай на весы.")
    end = time.time() + minutes * 60
    while time.time() < end:
        try:
            await one_cycle()
        except Exception as e:
            say(f"! ошибка цикла: {e!r}")
            await asyncio.sleep(1)
    say("Демон завершён.")


asyncio.run(main())
