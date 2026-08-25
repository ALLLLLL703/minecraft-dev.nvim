#!/usr/bin/env python3
"""Strict, dependency-free NBT <-> typed JSON codec for minecraft-dev.nvim."""

from __future__ import annotations

import argparse
import gzip
import json
import math
import struct
import sys
import zlib


TYPE_NAMES = (
    "end",
    "byte",
    "short",
    "int",
    "long",
    "float",
    "double",
    "byte_array",
    "string",
    "list",
    "compound",
    "int_array",
    "long_array",
)
TYPE_IDS = {name: index for index, name in enumerate(TYPE_NAMES)}


class CodecError(Exception):
    def __init__(self, code: str, detail: str):
        super().__init__(detail)
        self.code = code
        self.detail = detail


class Limits:
    def __init__(self, args: argparse.Namespace):
        self.max_input = args.max_input_bytes
        self.max_output = args.max_output_bytes
        self.max_depth = args.max_depth
        self.max_tags = args.max_tags
        self.max_array = args.max_array_length
        self.max_string = args.max_string_bytes
        self.tags = 0

    def tag(self, depth: int) -> None:
        if depth > self.max_depth:
            raise CodecError("depth_limit", f"NBT nesting exceeds {self.max_depth}")
        self.tags += 1
        if self.tags > self.max_tags:
            raise CodecError("tag_limit", f"NBT tag count exceeds {self.max_tags}")


class Reader:
    def __init__(self, data: bytes, limits: Limits):
        self.data = data
        self.offset = 0
        self.limits = limits

    def read(self, length: int) -> bytes:
        if length < 0 or self.offset + length > len(self.data):
            raise CodecError("malformed", "unexpected end of NBT input")
        result = self.data[self.offset : self.offset + length]
        self.offset += length
        return result

    def unpack(self, pattern: str):
        size = struct.calcsize(pattern)
        return struct.unpack(pattern, self.read(size))[0]

    def string(self) -> str:
        length = self.unpack(">H")
        if length > self.limits.max_string:
            raise CodecError("string_limit", f"NBT string exceeds {self.limits.max_string} bytes")
        return decode_modified_utf8(self.read(length))


class Writer:
    def __init__(self, limits: Limits):
        self.parts: list[bytes] = []
        self.length = 0
        self.limits = limits

    def write(self, data: bytes) -> None:
        self.parts.append(data)
        self.length += len(data)
        if self.length > self.limits.max_output:
            raise CodecError("size_limit", f"encoded NBT exceeds {self.limits.max_output} bytes")

    def pack(self, pattern: str, value) -> None:
        try:
            self.write(struct.pack(pattern, value))
        except (OverflowError, struct.error) as error:
            raise CodecError("value_range", str(error)) from error

    def string(self, value: str) -> None:
        if not isinstance(value, str):
            raise CodecError("invalid_text", "NBT names and strings must be strings")
        data = encode_modified_utf8(value)
        if len(data) > min(65535, self.limits.max_string):
            raise CodecError("string_limit", "NBT string is too long")
        self.pack(">H", len(data))
        self.write(data)

    def finish(self) -> bytes:
        return b"".join(self.parts)


def decode_modified_utf8(data: bytes) -> str:
    units: list[int] = []
    index = 0
    while index < len(data):
        first = data[index]
        if first <= 0x7F and first != 0:
            units.append(first)
            index += 1
        elif first & 0xE0 == 0xC0 and index + 1 < len(data):
            second = data[index + 1]
            if second & 0xC0 != 0x80:
                raise CodecError("malformed", "invalid modified UTF-8 continuation byte")
            value = ((first & 0x1F) << 6) | (second & 0x3F)
            if value != 0 and value < 0x80:
                raise CodecError("malformed", "overlong modified UTF-8 sequence")
            units.append(value)
            index += 2
        elif first & 0xF0 == 0xE0 and index + 2 < len(data):
            second, third = data[index + 1], data[index + 2]
            if second & 0xC0 != 0x80 or third & 0xC0 != 0x80:
                raise CodecError("malformed", "invalid modified UTF-8 continuation byte")
            value = ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F)
            if value < 0x800:
                raise CodecError("malformed", "overlong modified UTF-8 sequence")
            units.append(value)
            index += 3
        else:
            raise CodecError("malformed", "invalid modified UTF-8 sequence")
    raw = b"".join(struct.pack(">H", unit) for unit in units)
    try:
        return raw.decode("utf-16-be")
    except UnicodeDecodeError as error:
        raise CodecError("malformed", "invalid modified UTF-8 surrogate pair") from error


def encode_modified_utf8(value: str) -> bytes:
    try:
        raw = value.encode("utf-16-be")
    except UnicodeEncodeError as error:
        raise CodecError("invalid_text", "invalid Unicode string") from error
    result = bytearray()
    for index in range(0, len(raw), 2):
        unit = (raw[index] << 8) | raw[index + 1]
        if 0 < unit <= 0x7F:
            result.append(unit)
        elif unit <= 0x7FF:
            result.extend((0xC0 | (unit >> 6), 0x80 | (unit & 0x3F)))
        else:
            result.extend((0xE0 | (unit >> 12), 0x80 | ((unit >> 6) & 0x3F), 0x80 | (unit & 0x3F)))
    return bytes(result)


def checked_length(reader: Reader) -> int:
    length = reader.unpack(">i")
    if length < 0:
        raise CodecError("malformed", "NBT collection has a negative length")
    if length > reader.limits.max_array:
        raise CodecError("array_limit", f"NBT collection length exceeds {reader.limits.max_array}")
    return length


def number_for_json(value: float):
    if math.isnan(value):
        return "NaN"
    if math.isinf(value):
        return "Infinity" if value > 0 else "-Infinity"
    return value


def read_named_payload(reader: Reader, type_id: int, depth: int) -> dict:
    if not 0 < type_id < len(TYPE_NAMES):
        raise CodecError("unknown_tag", f"unknown NBT tag ID {type_id}")
    name = reader.string()
    if type_id == 10:
        reader.limits.tag(depth)
        values = []
        while True:
            child_id = reader.unpack(">B")
            if child_id == 0:
                break
            values.append(read_named_payload(reader, child_id, depth + 1))
        return {"type": "compound", "name": name, "value": values}
    node = read_payload(reader, type_id, depth)
    node["name"] = name
    return node


def read_list_payload(reader: Reader, type_id: int, depth: int) -> dict:
    if type_id == 10:
        reader.limits.tag(depth)
        values = []
        while True:
            child_id = reader.unpack(">B")
            if child_id == 0:
                break
            values.append(read_named_payload(reader, child_id, depth + 1))
        return {"type": "compound", "value": values}
    return read_payload(reader, type_id, depth)


def read_payload(reader: Reader, type_id: int, depth: int) -> dict:
    if not 0 < type_id < len(TYPE_NAMES):
        raise CodecError("unknown_tag", f"unknown NBT tag ID {type_id}")
    reader.limits.tag(depth)
    node: dict = {"type": TYPE_NAMES[type_id]}
    if type_id == 1:
        node["value"] = reader.unpack(">b")
    elif type_id == 2:
        node["value"] = reader.unpack(">h")
    elif type_id == 3:
        node["value"] = reader.unpack(">i")
    elif type_id == 4:
        node["value"] = str(reader.unpack(">q"))
    elif type_id == 5:
        node["value"] = number_for_json(reader.unpack(">f"))
    elif type_id == 6:
        node["value"] = number_for_json(reader.unpack(">d"))
    elif type_id == 7:
        raw = reader.read(checked_length(reader))
        node["value"] = [item - 256 if item > 127 else item for item in raw]
    elif type_id == 8:
        node["value"] = reader.string()
    elif type_id == 9:
        element_id = reader.unpack(">B")
        length = checked_length(reader)
        if element_id >= len(TYPE_NAMES) or (element_id == 0 and length != 0):
            raise CodecError("unknown_tag", f"invalid NBT list tag ID {element_id}")
        node["element_type"] = TYPE_NAMES[element_id]
        node["value"] = [read_list_payload(reader, element_id, depth + 1) for _ in range(length)]
    elif type_id == 10:
        values = []
        while True:
            child_id = reader.unpack(">B")
            if child_id == 0:
                break
            values.append(read_named_payload(reader, child_id, depth + 1))
        node["value"] = values
    elif type_id == 11:
        node["value"] = [reader.unpack(">i") for _ in range(checked_length(reader))]
    elif type_id == 12:
        node["value"] = [str(reader.unpack(">q")) for _ in range(checked_length(reader))]
    return node


def integer(value, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise CodecError("value_range", f"expected integer in range {minimum}..{maximum}")
    return value


def long_integer(value) -> int:
    if not isinstance(value, str) or not value or value.strip() != value:
        raise CodecError("invalid_text", "long values must be decimal strings")
    try:
        result = int(value, 10)
    except ValueError as error:
        raise CodecError("invalid_text", "invalid long decimal string") from error
    if not -(2**63) <= result < 2**63:
        raise CodecError("value_range", "long value is outside signed 64-bit range")
    return result


def floating(value) -> float:
    if isinstance(value, bool):
        raise CodecError("invalid_text", "floating value must be a number")
    if isinstance(value, (int, float)):
        return float(value)
    if value in ("NaN", "Infinity", "-Infinity"):
        return {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}[value]
    raise CodecError("invalid_text", "floating value must be a number or NaN/Infinity string")


def node_type(node: dict) -> int:
    if not isinstance(node, dict) or node.get("type") not in TYPE_IDS or node.get("type") == "end":
        raise CodecError("unknown_tag", f"unknown NBT tag type {node.get('type') if isinstance(node, dict) else node!r}")
    return TYPE_IDS[node["type"]]


def write_payload(writer: Writer, node: dict, depth: int, expected_type: int | None = None) -> None:
    type_id = node_type(node)
    if expected_type is not None and type_id != expected_type:
        raise CodecError("list_type", "NBT list items must match element_type")
    writer.limits.tag(depth)
    value = node.get("value")
    if type_id == 1:
        writer.pack(">b", integer(value, -128, 127))
    elif type_id == 2:
        writer.pack(">h", integer(value, -32768, 32767))
    elif type_id == 3:
        writer.pack(">i", integer(value, -(2**31), 2**31 - 1))
    elif type_id == 4:
        writer.pack(">q", long_integer(value))
    elif type_id == 5:
        writer.pack(">f", floating(value))
    elif type_id == 6:
        writer.pack(">d", floating(value))
    elif type_id in (7, 11, 12):
        if not isinstance(value, list) or len(value) > writer.limits.max_array:
            raise CodecError("array_limit", "NBT array is missing or too long")
        writer.pack(">i", len(value))
        for item in value:
            if type_id == 7:
                writer.pack(">b", integer(item, -128, 127))
            elif type_id == 11:
                writer.pack(">i", integer(item, -(2**31), 2**31 - 1))
            else:
                writer.pack(">q", long_integer(item))
    elif type_id == 8:
        writer.string(value)
    elif type_id == 9:
        element_name = node.get("element_type")
        if element_name not in TYPE_IDS:
            raise CodecError("unknown_tag", f"unknown NBT list element type {element_name!r}")
        element_id = TYPE_IDS[element_name]
        if not isinstance(value, list) or len(value) > writer.limits.max_array:
            raise CodecError("array_limit", "NBT list is missing or too long")
        if element_id == 0 and value:
            raise CodecError("list_type", "non-empty NBT list cannot use end element type")
        writer.pack(">B", element_id)
        writer.pack(">i", len(value))
        for item in value:
            write_payload(writer, item, depth + 1, element_id)
    elif type_id == 10:
        if not isinstance(value, list):
            raise CodecError("invalid_text", "NBT compound value must be an array of named tags")
        names = set()
        for item in value:
            child_id = node_type(item)
            name = item.get("name")
            if not isinstance(name, str):
                raise CodecError("invalid_text", "NBT compound children require string names")
            if name in names:
                raise CodecError("duplicate_name", f"duplicate NBT compound name {name!r}")
            names.add(name)
            writer.pack(">B", child_id)
            writer.string(name)
            write_payload(writer, item, depth + 1, child_id)
        writer.pack(">B", 0)


def decompress_limited(data: bytes, wbits: int, limit: int) -> bytes:
    try:
        decoder = zlib.decompressobj(wbits)
        result = decoder.decompress(data, limit + 1)
        if len(result) > limit or decoder.unconsumed_tail:
            raise CodecError("size_limit", f"decompressed NBT exceeds {limit} bytes")
        result += decoder.flush(limit + 1 - len(result))
        if len(result) > limit:
            raise CodecError("size_limit", f"decompressed NBT exceeds {limit} bytes")
        if not decoder.eof:
            raise CodecError("malformed", "truncated compressed NBT stream")
        if decoder.unused_data:
            raise CodecError("malformed", "trailing data after compressed NBT stream")
        return result
    except zlib.error as error:
        raise CodecError("malformed", f"invalid compressed NBT: {error}") from error


def decode(data: bytes, limits: Limits) -> tuple[dict, str]:
    if len(data) > limits.max_input:
        raise CodecError("size_limit", f"NBT input exceeds {limits.max_input} bytes")
    if data.startswith(b"\x1f\x8b"):
        compression = "gzip"
        data = decompress_limited(data, 16 + zlib.MAX_WBITS, limits.max_output)
    elif len(data) >= 2 and data[0] & 0x0F == 8 and (data[0] << 8 | data[1]) % 31 == 0:
        compression = "zlib"
        data = decompress_limited(data, zlib.MAX_WBITS, limits.max_output)
    else:
        compression = "none"
    reader = Reader(data, limits)
    type_id = reader.unpack(">B")
    if type_id != TYPE_IDS["compound"]:
        if type_id >= len(TYPE_NAMES):
            raise CodecError("unknown_tag", f"unknown NBT root tag ID {type_id}")
        raise CodecError("invalid_root", "NBT root tag must be a compound")
    root = read_named_payload(reader, type_id, 0)
    if reader.offset != len(data):
        raise CodecError("malformed", "trailing bytes after NBT root tag")
    return root, compression


def encode(document: dict, compression: str, limits: Limits) -> bytes:
    if node_type(document) != TYPE_IDS["compound"]:
        raise CodecError("invalid_root", "NBT root tag must be a compound")
    name = document.get("name")
    writer = Writer(limits)
    writer.pack(">B", TYPE_IDS["compound"])
    writer.string(name)
    write_payload(writer, document, 0, TYPE_IDS["compound"])
    raw = writer.finish()
    if compression == "gzip":
        result = gzip.compress(raw, mtime=0)
    elif compression == "zlib":
        result = zlib.compress(raw)
    else:
        result = raw
    if len(result) > limits.max_output:
        raise CodecError("size_limit", f"encoded NBT exceeds {limits.max_output} bytes")
    return result


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("mode", choices=("decode", "encode"))
    result.add_argument("--compression", choices=("none", "gzip", "zlib"), default="none")
    result.add_argument("--max-input-bytes", type=int, default=32 * 1024 * 1024)
    result.add_argument("--max-output-bytes", type=int, default=64 * 1024 * 1024)
    result.add_argument("--max-depth", type=int, default=128)
    result.add_argument("--max-tags", type=int, default=250000)
    result.add_argument("--max-array-length", type=int, default=1000000)
    result.add_argument("--max-string-bytes", type=int, default=1024 * 1024)
    return result


def main() -> int:
    args = parser().parse_args()
    limits = Limits(args)
    source = sys.stdin.buffer.read(limits.max_input + 1)
    if len(source) > limits.max_input:
        raise CodecError("size_limit", f"input exceeds {limits.max_input} bytes")
    if args.mode == "decode":
        document, compression = decode(source, limits)
        result = compression.encode("ascii") + b"\n" + json.dumps(
            document,
            ensure_ascii=False,
            indent=2,
            allow_nan=False,
        ).encode("utf-8") + b"\n"
    else:
        try:
            document = json.loads(source.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise CodecError("invalid_text", str(error)) from error
        result = encode(document, args.compression, limits)
    if len(result) > limits.max_output:
        raise CodecError("size_limit", f"output exceeds {limits.max_output} bytes")
    sys.stdout.buffer.write(result)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CodecError as error:
        sys.stderr.write(json.dumps({"code": error.code, "detail": error.detail}) + "\n")
        raise SystemExit(2)
