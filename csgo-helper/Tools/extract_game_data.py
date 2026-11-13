#!/usr/bin/env python3
"""Читать архивы VPK v1-v2 CS:GO / CS2, не изменяя игру.

Зачем нужен инструмент
----------------------
Helper никогда не читает память игры. Публичные таблицы разброса лежат в
Resources/patterns.json. Метаданные оружия (скорострельность, магазин, item id)
можно сверить со скриптами игры внутри pak01_dir.vpk. Скрипт извлекает эти
текстовые файлы только для чтения и показывает, что реально доступно.

Типичное использование:
    python3 Tools/extract_game_data.py --game "$HOME/Library/Application Support/Steam/steamapps/common/csgo legacy" --list
    python3 Tools/extract_game_data.py --game "<...>/csgo legacy" --scan-weapons --out /tmp/weapons.json
    python3 Tools/extract_game_data.py --vpk "<...>/csgo/pak01_dir.vpk" --extract "scripts/items/items_game.txt" --out-dir /tmp/csgo_scripts

Если в legacy-VPK нет scripts/weapon_*.txt (частое явление), helper обязан
использовать встроенные fallback/эвристические таблицы. Инструмент сообщает об
этом явно и никогда не делает вид, что таблица паттернов была найдена.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterable

VPK_SIGNATURE = 0x55AA1234
TERMINATOR = 0xFFFF


@dataclass(frozen=True)
class VPKEntry:
    path: str
    crc32: int
    preload_bytes: int
    preload: bytes
    archive_index: int
    offset: int
    length: int


class VPKError(RuntimeError):
    pass


class VPKArchive:
    def __init__(self, directory_vpk: Path):
        self.directory_vpk = directory_vpk
        self.version = 0
        self.tree_size = 0
        self.tree_start = 12
        self.data_start = 12
        self.entries: dict[str, VPKEntry] = {}
        self._archives: dict[Path, BinaryIO] = {}
        self._parse()

    def _read_cstring(self, data: bytes, offset: int) -> tuple[str, int]:
        end = data.find(b"\0", offset)
        if end < 0:
            raise VPKError("незавершённая строка в дереве каталога VPK")
        raw = data[offset:end]
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("latin-1")
        return text, end + 1

    def _parse(self) -> None:
        with self.directory_vpk.open("rb") as handle:
            header = handle.read(28)
        if len(header) < 12:
            raise VPKError("файл слишком мал для заголовка VPK")
        signature, version = struct.unpack_from("<II", header, 0)
        if signature != VPK_SIGNATURE:
            raise VPKError(f"неверная сигнатура VPK 0x{signature:08x}")
        if version not in (1, 2):
            raise VPKError(f"неподдерживаемая версия VPK {version}")
        self.version = version
        self.tree_size = struct.unpack_from("<I", header, 8)[0]
        self.tree_start = 12 if version == 1 else 28
        self.data_start = self.tree_start + self.tree_size
        file_size = self.directory_vpk.stat().st_size
        if self.data_start > file_size:
            raise VPKError("дерево каталога больше файла VPK")
        with self.directory_vpk.open("rb") as handle:
            handle.seek(self.tree_start)
            tree = handle.read(self.tree_size)
        if len(tree) != self.tree_size:
            raise VPKError("неполное чтение дерева каталога VPK")
        offset = 0
        while offset < len(tree):
            if tree[offset] == 0:
                break
            extension, offset = self._read_cstring(tree, offset)
            while offset < len(tree):
                path, offset = self._read_cstring(tree, offset)
                if path == "":
                    break
                while offset < len(tree):
                    name, offset = self._read_cstring(tree, offset)
                    if name == "":
                        break
                    if offset + 18 > len(tree):
                        raise VPKError("обрезанная запись VPK")
                    crc32, preload_bytes, archive_index, entry_offset, entry_length, terminator = struct.unpack_from(
                        "<IHHIIH", tree, offset
                    )
                    offset += 18
                    if terminator != TERMINATOR:
                        raise VPKError(f"неверный терминатор записи VPK 0x{terminator:04x}")
                    if offset + preload_bytes > len(tree):
                        raise VPKError("обрезанные preload-данные VPK")
                    preload = tree[offset : offset + preload_bytes]
                    offset += preload_bytes
                    full = (path + "/" if path else "") + name
                    if extension:
                        full += "." + extension
                    self.entries[full.replace("\\", "/")] = VPKEntry(
                        path=full.replace("\\", "/"),
                        crc32=crc32,
                        preload_bytes=preload_bytes,
                        preload=preload,
                        archive_index=archive_index,
                        offset=entry_offset,
                        length=entry_length,
                    )
        if not self.entries:
            raise VPKError("из VPK не разобрано ни одной записи")

    def _archive_handle(self, index: int) -> BinaryIO:
        pattern = self.directory_vpk.name.replace("_dir.vpk", f"_{index:03d}.vpk")
        path = self.directory_vpk.with_name(pattern)
        if path not in self._archives:
            if not path.exists():
                raise VPKError(f"внешний архив не найден: {path}")
            self._archives[path] = path.open("rb")
        return self._archives[path]

    def read(self, path: str) -> bytes:
        entry = self.entries.get(path)
        if entry is None:
            raise KeyError(path)
        if entry.archive_index == 0x7FFF:
            if entry.length == 0:
                return entry.preload
            with self.directory_vpk.open("rb") as handle:
                handle.seek(self.data_start + entry.offset)
                return entry.preload + handle.read(entry.length)
        archive = self._archive_handle(entry.archive_index)
        archive.seek(entry.offset)
        return entry.preload + archive.read(entry.length)

    def close(self) -> None:
        for handle in self._archives.values():
            handle.close()
        self._archives.clear()

    def __enter__(self) -> "VPKArchive":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def find_vpk(game_dir: Path) -> Path:
    candidates = [
        game_dir / "csgo" / "pak01_dir.vpk",
        game_dir / "game" / "csgo" / "pak01_dir.vpk",
        game_dir / "pak01_dir.vpk",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"pak01_dir.vpk не найден в {game_dir}")


def parse_weapon_script(text: str) -> dict[str, str]:
    """Извлечь пары key/value верхнего уровня из скрипта оружия Source."""
    values: dict[str, str] = {}
    for match in re.finditer(r'^\s*"([^"]+)"\s+"([^"]*)"', text, flags=re.MULTILINE):
        key, value = match.group(1), match.group(2)
        values.setdefault(key, value)
    return values


def scan_weapons(archive: VPKArchive) -> dict[str, object]:
    weapon_entries = sorted(
        path for path in archive.entries
        if path.lower().startswith("scripts/weapon_") and path.lower().endswith(".txt")
    )
    items = [path for path in archive.entries if path.lower() == "scripts/items/items_game.txt"]
    report: dict[str, object] = {
        "vpk": str(archive.directory_vpk),
        "version": archive.version,
        "entries": len(archive.entries),
        "weaponScripts": [],
        "itemsGame": bool(items),
        "note": "",
    }
    scripts = []
    for path in weapon_entries:
        text = archive.read(path).decode("utf-8", errors="replace")
        parsed = parse_weapon_script(text)
        cycle = parsed.get("cycletime") or parsed.get("CycleTime")
        rpm = None
        if cycle:
            try:
                rpm = round(60.0 / float(cycle))
            except (ValueError, ZeroDivisionError):
                rpm = None
        scripts.append({
            "path": path,
            "printname": parsed.get("printname"),
            "maxclip": parsed.get("maxclip"),
            "cycletime": cycle,
            "rpm": rpm,
            "price": parsed.get("price"),
            "weapon_type": parsed.get("weapon_type"),
        })
    report["weaponScripts"] = scripts
    if not weapon_entries:
        report["note"] = (
            "scripts/weapon_*.txt отсутствуют в этом VPK. "
            "Параметры оружия в Resources/patterns.json поэтому взяты из каталога; "
            "паттерны — из spray.training (MIT) и документированной fallback-эвристики."
        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--game", type=Path, help="каталог установки CS:GO с csgo/pak01_dir.vpk")
    source.add_argument("--vpk", type=Path, help="явный путь к pak01_dir.vpk")
    parser.add_argument("--list", action="store_true", help="показать подходящие файлы скриптов")
    parser.add_argument("--extract", action="append", default=[], help="извлечь путь или glob (можно повторять)")
    parser.add_argument("--out-dir", type=Path, help="каталог назначения для --extract")
    parser.add_argument("--scan-weapons", action="store_true", help="разобрать скрипты оружия и вывести JSON")
    parser.add_argument("--out", type=Path, help="записать JSON-отчёт сюда")
    parser.add_argument("--all", action="store_true", help="с --list показать все записи VPK")
    args = parser.parse_args()

    try:
        vpk_path = args.vpk or find_vpk(args.game)
        with VPKArchive(vpk_path) as archive:
            print(
                f"VPK: {vpk_path}\nверсия={archive.version}, записей={len(archive.entries)}, "
                f"дерево={archive.tree_size}, данные с {archive.data_start}",
                file=sys.stderr,
            )
            matching = [
                path for path in sorted(archive.entries)
                if args.all or "scripts/weapon_" in path.lower() or path.lower() == "scripts/items/items_game.txt"
            ]
            if args.list or not (args.extract or args.scan_weapons):
                for path in matching:
                    print(path)
                if not matching:
                    print("скрипты weapon_* и items_game.txt не найдены; нужны fallback-таблицы", file=sys.stderr)
                if not args.extract and not args.scan_weapons:
                    return 0

            if args.extract:
                import fnmatch
                if not args.out_dir:
                    parser.error("для --extract требуется --out-dir")
                extracted = 0
                for pattern in args.extract:
                    for path in sorted(archive.entries):
                        if fnmatch.fnmatch(path, pattern):
                            destination = args.out_dir / path
                            destination.parent.mkdir(parents=True, exist_ok=True)
                            destination.write_bytes(archive.read(path))
                            extracted += 1
                            print(f"извлечено {path} -> {destination}", file=sys.stderr)
                if extracted == 0:
                    print("ни один файл не совпал с шаблонами --extract", file=sys.stderr)
                    return 2

            if args.scan_weapons:
                report = scan_weapons(archive)
                text = json.dumps(report, indent=2, ensure_ascii=False)
                if args.out:
                    args.out.parent.mkdir(parents=True, exist_ok=True)
                    args.out.write_text(text + "\n", encoding="utf-8")
                    print(f"отчёт -> {args.out}", file=sys.stderr)
                else:
                    print(text)
        return 0
    except (OSError, VPKError, KeyError) as error:
        print(f"ошибка: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
