#!/usr/bin/env python3
"""Generate minimal OpenType CFF and CFF2 fixtures for Specimen Press tests."""

from __future__ import annotations

import struct
from pathlib import Path

GLYPH_COUNT = 28
UNITS_PER_EM = 1000
ASCENDER = 800
DESCENDER = -200
LINE_GAP = 200
ADVANCE = 600


def encode_int(value: int) -> bytes:
    if -107 <= value <= 107:
        return bytes([value + 139])
    if 108 <= value <= 1131:
        value -= 108
        return bytes([247 + (value >> 8), value & 0xFF])
    if -1131 <= value <= -108:
        value = -value - 108
        return bytes([251 + (value >> 8), value & 0xFF])
    if -32768 <= value <= 32767:
        return bytes([28, (value >> 8) & 0xFF, value & 0xFF])
    return bytes([29, (value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


def charstring_empty() -> bytes:
    return bytes([14])


def charstring_box(width: int = 400, height: int = 700) -> bytes:
  # Simple rectangle: (100,0) -> (100,height) -> (100+width,height) -> (100+width,0)
    parts = [
        encode_int(100),
        encode_int(0),
        bytes([21]),  # rmoveto
        encode_int(0),
        encode_int(height),
        bytes([5]),  # rlineto
        encode_int(width),
        encode_int(0),
        bytes([5]),
        encode_int(0),
        encode_int(-height),
        bytes([5]),
        bytes([14]),  # endchar
    ]
    return b"".join(parts)


def charstring_a() -> bytes:
    # Triangle-like A shape
    parts = [
        encode_int(100),
        encode_int(0),
        bytes([21]),
        encode_int(200),
        encode_int(700),
        bytes([5]),
        encode_int(200),
        encode_int(-700),
        bytes([5]),
        encode_int(100),
        encode_int(350),
        bytes([5]),
        encode_int(100),
        encode_int(-350),
        bytes([5]),
        bytes([14]),
    ]
    return b"".join(parts)


def build_index(items: list[bytes], wide_count: bool = False) -> bytes:
    if not items:
        if wide_count:
            return struct.pack(">HI", 0, 0)
        return struct.pack(">H", 0)

    off_size = 1
    max_offset = sum(len(item) for item in items)
    while max_offset >= 256 ** off_size:
        off_size += 1

    header = struct.pack(">H", 0xFFFF) if wide_count else struct.pack(">H", len(items))
    if wide_count:
        header += struct.pack(">I", len(items))
    header += bytes([off_size])

    offsets = [1]
    running = 1
    for item in items:
        running += len(item)
        offsets.append(running)

    for offset in offsets:
        header += offset.to_bytes(off_size, "big")
    header += b"".join(items)
    return header


def build_dict(entries: list[tuple[list[int], int]]) -> bytes:
    data = bytearray()
    for operands, operator in entries:
        for operand in operands:
            data.extend(encode_int(operand))
        if operator >= 1000:
            data.extend([12, operator - 1000])
        else:
            data.append(operator)
    return bytes(data)


def build_cff_payload(is_cff2: bool) -> bytes:
    family = "Specimen Press CFF2" if is_cff2 else "Specimen Press CFF"
    strings = [family, family, family]
    string_index = build_index([s.encode("ascii") for s in strings])

    charstrings = [charstring_empty(), charstring_empty()]
    for index in range(2, GLYPH_COUNT):
        charstrings.append(charstring_a() if index == 2 else charstring_box())
    charstrings_index = build_index(charstrings, wide_count=is_cff2)

    private_dict = build_dict([])
    local_subrs = build_index([], wide_count=is_cff2)

    header = bytes([2, 0, 5, 0, 0]) if is_cff2 else bytes([1, 0, 4, 1])
    name_index = build_index([family.encode("ascii")], wide_count=is_cff2)
    global_subrs = build_index([], wide_count=is_cff2)
    charstrings_key = 17 if is_cff2 else 14

    def assemble(top_dict: bytes) -> tuple[bytes, int, int]:
        if is_cff2:
            header_bytes = bytes([2, 0, 5]) + struct.pack(">H", len(top_dict))
            result = bytearray()
            result.extend(header_bytes)
            result.extend(top_dict)
            result.extend(string_index)
            result.extend(global_subrs)
            charstrings_offset = len(result)
            result.extend(charstrings_index)
            private_offset = len(result)
            result.extend(private_dict)
            result.extend(local_subrs)
            return bytes(result), charstrings_offset, private_offset

        top_dict_index = build_index([top_dict], wide_count=False)
        result = bytearray()
        result.extend(header)
        result.extend(name_index)
        result.extend(top_dict_index)
        result.extend(string_index)
        result.extend(global_subrs)
        charstrings_offset = len(result)
        result.extend(charstrings_index)
        private_offset = len(result)
        result.extend(private_dict)
        result.extend(local_subrs)
        return bytes(result), charstrings_offset, private_offset

    charstrings_offset = 0
    private_offset = 0
    for _ in range(4):
        top_dict = build_dict([
            ([0, 0, 1000, 800], 5),
            ([0], 15),
            ([charstrings_offset], charstrings_key),
            ([len(private_dict), private_offset], 18),
        ])
        result, charstrings_offset, private_offset = assemble(top_dict)
    return result


def checksum(data: bytes) -> int:
    if len(data) % 4:
        data += b"\0" * (4 - len(data) % 4)
    total = 0
    for index in range(0, len(data), 4):
        total = (total + struct.unpack(">I", data[index : index + 4])[0]) & 0xFFFFFFFF
    return total


def build_cmap() -> bytes:
    # Format 4 cmap: space (32) and A-Z (65-90)
    segments = [(32, 32, -31, 0), (65, 90, -63, 0), (0xFFFF, 0xFFFF, 1, 0)]
    seg_count = len(segments)
    length = 16 + seg_count * 8
    data = struct.pack(">HHHHH", 4, length, 0, 2 * seg_count, 2)
    end_codes = b"".join(struct.pack(">H", end) for start, end, _, _ in segments)
    data += end_codes + b"\0\0"
    data += b"".join(struct.pack(">H", start) for start, _, _, _ in segments)
    data += b"".join(struct.pack(">h", delta) for _, _, delta, _ in segments)
    data += b"".join(struct.pack(">H", ro) for *_, ro in segments)
    return struct.pack(">HH", 0, 1) + struct.pack(">HHI", 3, 1, 12) + data


def build_hmtx() -> bytes:
    data = bytearray()
    for _ in range(GLYPH_COUNT):
        data.extend(struct.pack(">Hh", ADVANCE, 0))
    return bytes(data)


def build_name(family: str) -> bytes:
    encoded = family.encode("utf-16-be")
    record = struct.pack(">HHHHHH", 3, 1, 0x0409, 1, len(encoded), 0)
    return struct.pack(">HHH", 0, 1, 12) + record + encoded


def build_head() -> bytes:
    return struct.pack(
        ">IIIIHHqqhhhhHHhhh",
        0x0001_0000,
        0x0001_0000,
        0,
        0x5F0F_3CF5,
        0,
        UNITS_PER_EM,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    )


def build_hhea() -> bytes:
    data = struct.pack(
        ">IhhhhHHhhhhHHhh",
        0x0001_0000,
        ASCENDER,
        DESCENDER,
        LINE_GAP,
        ADVANCE,
        0,
        0,
        ADVANCE,
        1,
        0,
        0,
        0,
        0,
        0,
        GLYPH_COUNT,
    )
    return data + b"\0\0\0\0"


def build_maxp() -> bytes:
    return struct.pack(">IH", 0x0001_0000, GLYPH_COUNT)


def build_post() -> bytes:
    return struct.pack(">IhhhhH", 0x0003_0000, 0, 0, 0, 0, 0)


def build_font(path: Path, is_cff2: bool) -> None:
    family = "Specimen Press CFF2" if is_cff2 else "Specimen Press CFF"
    cff_tag = "CFF2" if is_cff2 else "CFF "
    tables = {
        "head": build_head(),
        "hhea": build_hhea(),
        "hmtx": build_hmtx(),
        "maxp": build_maxp(),
        "name": build_name(family),
        "cmap": build_cmap(),
        cff_tag: build_cff_payload(is_cff2),
        "post": build_post(),
    }

    num_tables = len(tables)
    search_range = 1
    while search_range * 2 <= num_tables:
        search_range *= 2
    entry_selector = 0
    value = search_range
    while value > 1:
        entry_selector += 1
        value //= 2
    range_shift = num_tables * 16 - search_range * 16

    records = []
    cursor = 12 + num_tables * 16
    for tag in sorted(tables):
        data = tables[tag]
        padded = data + b"\0" * ((4 - len(data) % 4) % 4)
        records.append((tag, padded, cursor))
        cursor += len(padded)

    header = struct.pack(
        ">IHHHH",
        0x4F54_544F,
        num_tables,
        search_range,
        entry_selector,
        range_shift,
    )
    directory = bytearray()
    for tag, data, offset in records:
        tag_bytes = tag.encode("ascii").ljust(4, b"\0")[:4]
        chk = checksum(data)
        directory.extend(tag_bytes)
        directory.extend(struct.pack(">III", chk, offset, len(data)))

    output = bytearray(header)
    output.extend(directory)
    for _, data, _ in records:
        output.extend(data)

    path.write_bytes(output)
    print(f"Wrote {path} ({len(output)} bytes)")


def main() -> None:
    resources = Path(__file__).resolve().parent.parent / "Sources" / "SpecimenPress" / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    build_font(resources / "SpecimenPressCFF.otf", is_cff2=False)
    build_font(resources / "SpecimenPressCFF2.otf", is_cff2=True)


if __name__ == "__main__":
    main()
