#!/usr/bin/env python3
"""Validate bundled CFF fixtures without Swift."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


def read_u16(data: bytes, offset: int) -> int:
    return struct.unpack(">H", data[offset : offset + 2])[0]


def read_tables(data: bytes) -> dict[str, tuple[int, int]]:
    num_tables = read_u16(data, 4)
    tables: dict[str, tuple[int, int]] = {}
    for index in range(num_tables):
        record = 12 + index * 16
        tag = data[record : record + 4].decode("ascii").rstrip("\0")
        offset, length = struct.unpack(">II", data[record + 8 : record + 16])
        tables[tag] = (offset, length)
    return tables


def decode_operand(data: bytes, cursor: int) -> tuple[int, int]:
    byte = data[cursor]
    cursor += 1
    if 32 <= byte <= 246:
        return byte - 139, cursor
    if 247 <= byte <= 250:
        return (byte - 247) * 256 + data[cursor] + 108, cursor + 1
    if 251 <= byte <= 254:
        return -((byte - 251) * 256 + data[cursor] + 108), cursor + 1
    if byte == 28:
        value = (data[cursor] << 8) | data[cursor + 1]
        if value >= 0x8000:
            value -= 0x10000
        return value, cursor + 2
    if byte == 29:
        value = struct.unpack(">i", data[cursor : cursor + 4])[0]
        return value, cursor + 4
    raise ValueError(f"unsupported operand {byte}")


def read_index(data: bytes, offset: int) -> tuple[list[bytes], int]:
    count = read_u16(data, offset)
    count_size = 2
    if count == 0xFFFF:
        count = struct.unpack(">I", data[offset + 2 : offset + 6])[0]
        count_size = 6
    if count == 0:
        return [], offset + count_size
    off_size = data[offset + count_size]
    offsets_start = offset + count_size + 1
    data_start = offsets_start + (count + 1) * off_size
    items: list[bytes] = []
    for index in range(count):
        start = int.from_bytes(
            data[offsets_start + index * off_size : offsets_start + (index + 1) * off_size],
            "big",
        ) - 1
        end = int.from_bytes(
            data[offsets_start + (index + 1) * off_size : offsets_start + (index + 2) * off_size],
            "big",
        ) - 1
        items.append(data[data_start + start : data_start + end])
    last_offset = int.from_bytes(
        data[offsets_start + count * off_size : offsets_start + (count + 1) * off_size], "big"
    )
    return items, data_start + last_offset - 1


def skip_index(data: bytes, offset: int) -> int:
    return read_index(data, offset)[1]


def parse_dict(data: bytes) -> dict[int, int]:
    offsets: dict[int, int] = {}
    operands: list[int] = []
    cursor = 0
    while cursor < len(data):
        byte = data[cursor]
        cursor += 1
        if byte >= 32:
            cursor -= 1
            value, cursor = decode_operand(data, cursor)
            operands.append(value)
            continue
        operator = 1000 + data[cursor] if byte == 12 else byte
        if byte == 12:
            cursor += 1
        if operator in (14, 17) and operands:
            offsets[operator] = operands[-1]
        operands.clear()
    return offsets


def validate(path: Path, is_cff2: bool) -> None:
    data = path.read_bytes()
    signature = struct.unpack(">I", data[0:4])[0]
    assert signature == 0x4F54_544F, path.name
    tables = read_tables(data)
    tag = "CFF2" if is_cff2 else "CFF "
    assert tag in tables, f"missing {tag}"
    base, length = tables[tag]
    cff = data[base : base + length]
    assert cff[0] == (2 if is_cff2 else 1), path.name

    if is_cff2:
        hdr_size = cff[2]
        top_dict_length = struct.unpack(">H", cff[3:5])[0]
        top_dict = cff[hdr_size : hdr_size + top_dict_length]
        cursor = base + hdr_size + top_dict_length
        cursor = skip_index(data, cursor)
        global_subrs, _ = read_index(data, cursor)
    else:
        cursor = base + cff[2]
        cursor = skip_index(data, cursor)
        top_items, _ = read_index(data, cursor)
        top_dict = top_items[0]
        cursor = skip_index(data, cursor)
        cursor = skip_index(data, cursor)
        global_subrs, _ = read_index(data, cursor)

    top_offsets = parse_dict(top_dict)
    key = 17 if is_cff2 else 14
    assert key in top_offsets, f"{path.name} missing CharStrings offset"
    charstrings, _ = read_index(data, base + top_offsets[key])
    assert len(charstrings) == 28, f"{path.name} expected 28 charstrings"
    assert charstrings[2], f"{path.name} glyph A charstring is empty"
    print(f"OK {path.name}: {len(charstrings)} charstrings, glyph A length {len(charstrings[2])}")


def main() -> int:
    resources = Path(__file__).resolve().parent.parent / "Sources" / "SpecimenPress" / "Resources"
    validate(resources / "SpecimenPressCFF.otf", is_cff2=False)
    validate(resources / "SpecimenPressCFF2.otf", is_cff2=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
