#!/usr/bin/env python3
"""Собрать Resources/patterns.json из измеренных и эвристических источников.

Измеренные кумулятивные таблицы разброса взяты из проекта под лицензией MIT
https://github.com/RoyZ-iwnl/spray.training (js/weapons.js). Таблицы хранятся
в экранных пикселях этого проекта ([горизонталь, вертикаль-вверх]) и
переводятся в кумулятивные градусы компенсации в *мышиных* координатах:

    x = -horizontal * DEGREES_PER_UNIT
    y = +vertical   * DEGREES_PER_UNIT   (в macOS +y мыши направлена вниз)

Оружие без измеренной таблицы получает детерминированную, явно помеченную
эвристическую кривую. Эвристика — правдоподобная форма, а не телеметрия.
Она достаточно полезна для оружия без публичной таблицы, но её нельзя
выдавать за измеренные данные.

Скрипт детерминирован: без меток времени, со стабильными seed и сортировкой.
Запускать из каталога csgo-helper:

    python3 Tools/build_patterns.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
from pathlib import Path
from typing import Any

DEGREES_PER_UNIT = 0.029
ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "Tools" / "data" / "weapon_catalog.json"
MEASURED_PATH = ROOT / "Tools" / "data" / "spray_training_patterns.json"
OUTPUT_PATH = ROOT / "Resources" / "patterns.json"

# Амплитуда горизонтального качания (градусы) и показатель вертикального
# подъёма для каждого класса оружия.
FALLBACK_PROFILE: dict[str, tuple[float, float]] = {
    "rifle": (2.6, 0.72),
    "smg": (2.2, 0.68),
    "lmg": (3.2, 0.70),
    "sniper": (1.5, 0.80),
    "pistol": (1.3, 0.66),
    "shotgun": (1.0, 0.75),
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def seed_for(weapon_id: str) -> int:
    digest = hashlib.sha256(f"csgo-helper-fallback-v1:{weapon_id}".encode()).digest()
    return int.from_bytes(digest[:8], "big")


def fallback_pattern(weapon: dict[str, Any]) -> list[list[float]]:
    """Вернуть кумулятивные градусы [x, y]; первая точка — (0, 0)."""
    weapon_id = weapon["id"]
    cls = weapon.get("class", "rifle")
    total_y = float(weapon["fallbackTotalY"])
    shots = int(weapon["magazine"])
    amplitude, exponent = FALLBACK_PROFILE.get(cls, (2.0, 0.7))
    rng = random.Random(seed_for(weapon_id))
    phase_a = rng.uniform(0.0, math.tau)
    phase_b = rng.uniform(0.0, math.tau)
    random_walk = 0.0
    points: list[list[float]] = [[0.0, 0.0]]
    previous_y = 0.0
    for index in range(1, max(2, shots)):
        t = index / float(max(2, shots) - 1)
        # Вертикальный подъём смещён к началу, с небольшим детерминированным колебанием.
        climb = total_y * (t ** exponent)
        climb += total_y * 0.018 * math.sin(math.tau * 2.1 * t + phase_b) * t
        climb = max(previous_y, climb)
        previous_y = climb
        random_walk += rng.uniform(-0.12, 0.12)
        sway = (
            0.45 * math.sin(math.tau * 1.15 * t + phase_a)
            + 0.25 * math.sin(math.tau * 2.30 * t + phase_b)
            + 0.35 * random_walk
        )
        x = amplitude * (t ** 0.85) * sway
        points.append([round(x, 5), round(climb, 5)])
    return points


def measured_pattern(weapon: dict[str, Any], measured: dict[str, Any], source_key: str) -> list[list[float]]:
    raw_points = measured["cumulative_px"]
    if len(raw_points) < 2:
        raise ValueError(f"{weapon['id']}: measured table has fewer than two points")
    if raw_points[0] != [0.0, 0.0] and raw_points[0] != [0, 0]:
        raise ValueError(f"{weapon['id']}: measured table must start at [0, 0]")
    points: list[list[float]] = []
    for horizontal, vertical_up in raw_points:
        x = -float(horizontal) * DEGREES_PER_UNIT
        y = float(vertical_up) * DEGREES_PER_UNIT
        points.append([round(x, 5), round(y, 5)])
    if len(points) != int(weapon["magazine"]):
        # Измеренные таблицы обычно покрывают ровно один магазин. Если таблица
        # длиннее, обрезаем её; если короче — продлеваем хвост измеренным
        # наклоном. Продление детерминировано и описано в README; качество
        # остаётся measured, потому что исходные данные измерены.
        magazine = int(weapon["magazine"])
        if len(points) > magazine:
            points = points[:magazine]
        else:
            while len(points) < magazine:
                previous = points[-1]
                before = points[-2]
                dx = previous[0] - before[0]
                dy = previous[1] - before[1]
                points.append([round(previous[0] + dx * 0.85, 5), round(previous[1] + dy * 0.85, 5)])
    return points


def per_shot(points: list[list[float]]) -> list[list[float]]:
    increments: list[list[float]] = []
    for index in range(1, len(points)):
        increments.append(
            [
                round(points[index][0] - points[index - 1][0], 5),
                round(points[index][1] - points[index - 1][1], 5),
            ]
        )
    return increments


def build() -> dict[str, Any]:
    catalog = load_json(CATALOG_PATH)
    measured = load_json(MEASURED_PATH)["weapons"]
    weapons_out: list[dict[str, Any]] = []
    source_counts = {"measured": 0, "heuristic": 0}
    seen: set[str] = set()

    for weapon in catalog["weapons"]:
        weapon_id = weapon["id"]
        if weapon_id in seen:
            raise ValueError(f"duplicate weapon id: {weapon_id}")
        seen.add(weapon_id)
        source_key = weapon.get("sourcePattern")
        base = {
            "id": weapon_id,
            "displayName": weapon["displayName"],
            "aliases": weapon.get("aliases", []),
            "itemDef": weapon.get("itemDef"),
            "class": weapon["class"],
            "fireMode": weapon["fireMode"],
            "rpm": weapon["rpm"],
            "magazine": weapon["magazine"],
            "reloadMs": weapon.get("reloadMs", 0),
            "pellets": weapon.get("pellets", 1),
            "scoped": bool(weapon.get("scoped", False)),
            "recommendedHoldMs": 120 if weapon["fireMode"] == "automatic" else 40,
        }
        if source_key and source_key in measured:
            points = measured_pattern(weapon, measured[source_key], source_key)
            quality = "measured"
            pattern_source = "spray.training (MIT, js/weapons.js)"
            base["sourcePattern"] = source_key
            source_counts["measured"] += 1
        else:
            points = fallback_pattern(weapon)
            quality = "heuristic"
            pattern_source = "детерминированная fallback-эвристика v1 (не телеметрия)"
            source_counts["heuristic"] += 1
        base["patternSource"] = pattern_source
        base["quality"] = quality
        base["cumulativeDegrees"] = points
        base["perShotDegrees"] = per_shot(points)
        weapons_out.append(base)

    if len(weapons_out) != 33:
        print(f"предупреждение: ожидалось 33 профиля, создано {len(weapons_out)}", file=sys.stderr)

    return {
        "schemaVersion": 1,
        "units": "degrees",
        "coordinateSpace": "кумулятивная поправка прицела в координатах мыши (+x вправо, +y вниз)",
        "degreesPerSourceUnit": DEGREES_PER_UNIT,
        "notes": (
            "Измеренные таблицы пересчитаны из экранных единиц spray.training. "
            "Эвристические профили помечены quality=heuristic и не являются телеметрией. "
            "Первая точка — первый выстрел, всегда [0, 0]."
        ),
        "sources": {
            "measured": {
                "name": "spray.training",
                "url": "https://github.com/RoyZ-iwnl/spray.training",
                "license": "MIT",
                "copyright": "Copyright (c) 2018 Robin Park",
            },
            "guide": {
                "name": "Steam guide 2830373896",
                "url": "https://steamcommunity.com/sharedfiles/filedetails/?id=2830373896",
                "use": "сверка и будущие измеренные таблицы; не включён как игровые данные",
            },
            "fallback": {
                "name": "CSGO Helper deterministic fallback v1",
                "method": "вертикальный подъём с упором в начало + детерминированное горизонтальное качание",
            },
        },
        "counts": {
            "total": len(weapons_out),
            "measured": source_counts["measured"],
            "heuristic": source_counts["heuristic"],
        },
        "weapons": weapons_out,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    args = parser.parse_args()
    data = build()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(
        f"записано {args.output} ({args.output.stat().st_size} байт): "
        f"{data['counts']['total']} профилей, "
        f"{data['counts']['measured']} измерено, {data['counts']['heuristic']} эвристика"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
