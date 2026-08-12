#!/usr/bin/env python3
"""Полный клиент протокола QN (Qingniu/Yolanda) для весов Libra CS20C1.

Кадр: [опкод][длина][версия протокола][...данные...][сумма = сумма предыдущих % 256]

Обмен:
  весы → 0x12  «привет»: MAC, версия, множитель веса (байт 10: 1 → /100, иначе /10)
  мы   → 0x13  единицы измерения (0x01 = кг)
  мы   → 0x02  текущее время (4 байта LE, эпоха с 2000-01-01)
  весы → 0x14  «настройки приняты»
  мы   → 0x20  синхронизация времени
  весы → 0x10  измерение: вес (байты 3-4 BE), стабильность (байт 5), импеданс (6-9)
  мы   → 0x22  запрос сохранённых измерений (если живых нет)
  весы → 0x23  сохранённое измерение (вес в байтах 10-11 BE /100)

Запуск:  open -n -a BLEScan.app --args <путь>/qnscale.py [минут]
Лог: qn_out.txt, измерения: measurements.csv
"""
import asyncio, os, sys, time
from datetime import datetime

from bleak import BleakScanner, BleakClient

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = open(os.path.join(HERE, "qn_out.txt"), "w", buffering=1)
CSV = os.path.join(HERE, "measurements.csv")

TARGET_NAME = "QN-Scale"
CH_NOTIFY = "0000fff1-0000-1000-8000-00805f9b34fb"
CH_WRITE = "0000fff2-0000-1000-8000-00805f9b34fb"
QN_EPOCH_OFFSET = 946_702_800  # как в openScale
UNIT_KG = 0x01

t0 = time.time()


def say(msg):
    print(msg, flush=True)
    OUT.write(f"{msg}\n")


def framed(payload: list[int]) -> bytes:
    """Кадр с контрольной суммой в последнем байте."""
    b = bytes(payload)
    return b + bytes([sum(b) & 0xFF])


def qn_time_bytes() -> list[int]:
    t = int(time.time()) - QN_EPOCH_OFFSET
    return [t & 0xFF, (t >> 8) & 0xFF, (t >> 16) & 0xFF, (t >> 24) & 0xFF]


def u16be(a: int, b: int) -> int:
    return (a << 8) | b


class Scale:
    def __init__(self, client):
        self.client = client
        self.proto = 0x15
        self.factor = 100.0
        self.configured = False
        self.last_data = time.time()
        self.stable_seen = False
        self.history_asked = 0

    # ---- отправка ----
    async def write(self, data: bytes, why: str):
        try:
            await self.client.write_gatt_char(CH_WRITE, data, response=True)
            say(f"           → {data.hex(' ')}   ({why})")
        except Exception as e:
            say(f"           ! не отправилось ({why}): {e}")

    async def configure(self):
        await self.write(framed([0x13, 0x09, self.proto, UNIT_KG, 0x10, 0x00, 0x00, 0x00]),
                         "единицы = кг")
        # кадр времени идёт без контрольной суммы
        await self.write(bytes([0x02] + qn_time_bytes()), "текущее время")

    async def time_sync(self):
        await self.write(framed([0x20, 0x08, self.proto] + qn_time_bytes()), "синхронизация времени")

    async def ask_history(self):
        self.history_asked += 1
        await self.write(framed([0x22, 0x06, self.proto, 0x00, 0x03]),
                         f"запрос истории #{self.history_asked}")

    # ---- разбор ----
    def record(self, kg: float, r1: int, r2: int, kind: str):
        line = f"{datetime.now():%Y-%m-%d %H:%M:%S},{kg:.2f},{r1},{r2},{kind}"
        with open(CSV, "a") as f:
            f.write(line + "\n")
        say(f"  *** ВЕС: {kg:.2f} кг   (импеданс {r1}/{r2}, {kind}) ***")

    def on_notify(self, sender, data: bytearray):
        d = bytes(data)
        self.last_data = time.time()
        ok = (sum(d[:-1]) & 0xFF) == d[-1]
        say(f"[{time.time() - t0:6.1f}s] ← {d.hex(' ')}{'' if ok else '  [!сумма]'}")
        op = d[0]

        if op == 0x12 and len(d) > 10:
            self.proto = d[2]
            # openScale считает делитель по байту 10 (1 → /100, иначе /10), но на CS20C1
            # там 0x05, а вес всё равно приходит в сотых долях кг. Поэтому делитель
            # выбираем по правдоподобности результата (см. разбор в 0x10).
            self.factor = 100.0
            mac = ":".join(f"{x:02x}" for x in d[3:9][::-1])
            say(f"  «привет»: MAC {mac}, версия {self.proto:#04x}, делитель веса {self.factor:.0f}")
            if not self.configured:
                self.configured = True
                asyncio.create_task(self.configure())

        elif op == 0x14:
            say("  настройки приняты → шлю синхронизацию времени")
            asyncio.create_task(self.time_sync())

        elif op == 0x10 and len(d) >= 10:
            raw = u16be(d[3], d[4])
            stable = d[5] == 1
            r1, r2 = u16be(d[6], d[7]), u16be(d[8], d[9])
            kg = raw / self.factor
            if not 2.0 <= kg <= 300.0:      # подстраховка, если попадётся ревизия с /10
                kg = raw / 10.0
            say(f"  измерение: сырое={raw} → {kg:.2f} кг, "
                f"{'ЗАФИКСИРОВАН' if stable else 'меняется'}, импеданс {r1}/{r2}")
            if stable and not self.stable_seen:
                self.stable_seen = True
                self.record(kg, r1, r2, "live")

        elif op == 0x23 and len(d) >= 17:
            kg = u16be(d[10], d[11]) / 100.0
            r1 = d[13] | (d[14] << 8)
            r2 = d[15] | (d[16] << 8)
            say(f"  сохранённое измерение: {kg:.2f} кг, импеданс {r1}/{r2}")
            if not self.stable_seen:
                self.stable_seen = True
                self.record(kg, r1, r2, "stored")

        elif op == 0xA1 or op == 0xA3:
            say("  подтверждение от весов")


async def one_cycle():
    dev = await BleakScanner.find_device_by_filter(
        lambda d, adv: (adv.local_name or d.name or "") == TARGET_NAME, timeout=30)
    if dev is None:
        return
    say(f"— весы проснулись, подключаюсь ({datetime.now():%H:%M:%S})")
    async with BleakClient(dev) as client:
        s = Scale(client)
        await client.start_notify(CH_NOTIFY, s.on_notify)
        say("  подписался на fff1, жду «привет»")
        asked = False
        while client.is_connected and time.time() - s.last_data < 40:
            await asyncio.sleep(0.3)
            # если живого веса нет — спрашиваем сохранённое
            if s.configured and not s.stable_seen and not asked and time.time() - s.last_data > 8:
                asked = True
                await s.ask_history()
        say(f"— сессия закрыта (вес получен: {'да' if s.stable_seen else 'нет'})")


async def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-psn")]
    minutes = float(args[0]) if args else 10
    say(f"Клиент QN запущен на {minutes:.0f} мин ({datetime.now():%H:%M:%S}). Наступай на весы.")
    end = time.time() + minutes * 60
    while time.time() < end:
        try:
            await one_cycle()
        except Exception as e:
            say(f"! ошибка: {e!r}")
            await asyncio.sleep(1)
    say("Завершено.")


asyncio.run(main())
