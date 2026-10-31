#!/usr/bin/env python3
"""Validate and patch the generated debug-XBE C tree with global symbol lookup.

The generated C files are split by function-count chunks. A call/reference in
one chunk does not imply that its function body is in that same file. This
validator first scans the complete generated tree, then patches the unique
actual definition (or, when the recompiler did not recognize the known guest
entry as a function, its exact generated unresolved-call placeholder).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import time

SYMBOL = "sub_0092FAD0"
MANUAL_SYMBOL = "sub_001E26E0"
MARKER = "/* DEBUG XBE PORT: use guarded manual Lua string interning */"


def _fmt_bytes(value: int) -> str:
    if value < 1024:
        return f"{value} B"
    if value < 1024 * 1024:
        return f"{value / 1024:.1f} KiB"
    return f"{value / (1024 * 1024):.1f} MiB"


def _fmt_time(seconds: float) -> str:
    seconds = max(0, int(seconds))
    return f"{seconds // 60:02d}:{seconds % 60:02d}"


def _progress(index: int, total: int, done_bytes: int, total_bytes: int,
              path: Path, started: float) -> None:
    pct = 100.0 if total_bytes == 0 else min(100.0, done_bytes * 100.0 / total_bytes)
    width = 24
    filled = min(width, int(pct * width / 100.0))
    bar = "#" * filled + "-" * (width - filled)
    print(
        f"[SCAN {index:02d}/{total:02d}] DONE [{bar}] {pct:5.1f}% "
        f"| {path.name} | {_fmt_bytes(done_bytes)}/{_fmt_bytes(total_bytes)} "
        f"| elapsed {_fmt_time(time.perf_counter() - started)}",
        flush=True,
    )


def _find_matching_brace(text: str, open_index: int) -> int:
    """Find the matching C brace while ignoring comments and quoted strings."""
    depth = 0
    state = "code"
    escaped = False
    i = open_index
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "line_comment":
            if ch == "\n":
                state = "code"
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 1
        elif state in ("string", "char"):
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif (state == "string" and ch == '"') or (state == "char" and ch == "'"):
                state = "code"
        else:
            if ch == "/" and nxt == "/":
                state = "line_comment"
                i += 1
            elif ch == "/" and nxt == "*":
                state = "block_comment"
                i += 1
            elif ch == '"':
                state = "string"
                escaped = False
            elif ch == "'":
                state = "char"
                escaped = False
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise RuntimeError("unbalanced braces while locating generated function")


def _definition_matches(text: str, symbol: str) -> list[re.Match[str]]:
    # Accept both ordinary split functions (brace on the next line) and the
    # translator's compact one-line unresolved-call placeholders.
    pattern = re.compile(
        r"(?m)^[ \t]*void[ \t]+" + re.escape(symbol) +
        r"[ \t]*\([ \t]*void[ \t]*\)[ \t\r\n]*\{"
    )
    return list(pattern.finditer(text))


def replace_guest_function_text(text: str, symbol: str, path: Path,
                                allow_unresolved_stub: bool = False) -> tuple[str, bool, str]:
    matches = _definition_matches(text, symbol)
    if not matches:
        return text, False, ""
    if len(matches) != 1:
        raise RuntimeError(f"{symbol}: expected one definition in {path.name}, found {len(matches)}")

    match = matches[0]
    open_index = text.find("{", match.start(), match.end())
    close_index = _find_matching_brace(text, open_index)
    end = close_index + 1
    current = text[match.start():end]
    if MARKER in current:
        already_kind = "manual-implementation-replacement" if path.name.lower() == "recomp_stubs_unresolved.c" else "translated-function"
        return text, True, already_kind

    is_stub = "not detected; minimal guest ret" in current and re.search(r"\besp\s*\+=\s*4\s*;", current) is not None
    if path.name.lower() == "recomp_stubs_unresolved.c":
        if not allow_unresolved_stub or not is_stub:
            raise RuntimeError(
                f"{symbol} is present in recomp_stubs_unresolved.c but is not the exact "
                "expected generated unresolved-call placeholder; refusing to overwrite it."
            )
        location_kind = "manual-implementation-replacement"
    else:
        if is_stub:
            raise RuntimeError(f"{symbol} unexpectedly appears as a generic unresolved stub in {path.name}.")
        location_kind = "translated-function"

    replacement = (
        f"extern void {MANUAL_SYMBOL}(void); /* reviewed manual Lua hash-chain repair */\n"
        f"void {symbol}(void)\n{{\n"
        f"    {MARKER}\n"
        f"    {MANUAL_SYMBOL}();\n"
        "}"
    )
    return text[:match.start()] + replacement + text[end:], True, location_kind


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fast, visible, global validation/normalization of generated debug-XBE C files."
    )
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--xbe-json", required=True, type=Path)
    parser.add_argument("--generated-root", required=True, type=Path)
    args = parser.parse_args()

    started = time.perf_counter()
    print("[DEBUG VALIDATOR] Starting global generated debug-XBE validation.", flush=True)
    print("[STEP 1/5] Reading XBE metadata and checking debug entry point...", flush=True)
    metadata = json.loads(args.xbe_json.read_text(encoding="utf-8"))
    if metadata.get("type") != "debug":
        raise SystemExit("The debug generated-code validator received a non-debug XBE.")
    entry = int(str(metadata["entry_point"]), 16)
    generic = f"sub_{entry:08X}".encode("ascii")
    public = b"xbe_entry_point"
    generated = args.generated_root
    header = generated / "recomp_funcs.h"
    dispatch = generated / "recomp_dispatch.c"
    if not header.is_file() or not dispatch.is_file():
        raise SystemExit("Generated function header or dispatch table is missing.")

    print("[STEP 2/5] Checking required debug-XBE generated symbols...", flush=True)
    header_data = header.read_bytes()
    dispatch_data = dispatch.read_bytes()
    required = (
        b"sub_0092FC10", b"sub_0092FAD0", b"sub_006FC9B0",
        b"sub_00955FC0", b"sub_00955E30",
    )
    for symbol in required:
        if symbol not in header_data:
            raise SystemExit(f"Required reviewed debug function {symbol.decode()} is absent from recomp_funcs.h.")
    if public not in header_data and generic not in header_data:
        raise SystemExit(f"Debug entry function {generic.decode()} is missing from recomp_funcs.h.")
    if public not in dispatch_data and generic not in dispatch_data:
        raise SystemExit(f"Debug entry function {generic.decode()} is missing from recomp_dispatch.c.")

    obsolete_stub = generated / "recomp_debug_retail_compat_stubs.c"
    source_files = sorted(
        path for path in generated.glob("recomp_*.c")
        if path.resolve() != obsolete_stub.resolve()
    )
    if not source_files:
        raise SystemExit("No generated recomp_*.c implementation files were found.")
    sizes = [path.stat().st_size for path in source_files]
    total_bytes = sum(sizes)
    print(
        f"[STEP 3/5] Global scan of {len(source_files)} generated C file(s) "
        f"({_fmt_bytes(total_bytes)} total). References and definitions may be in different chunks.",
        flush=True,
    )
    print(
        "[INFO] The scan reads the whole split tree before deciding where the function body lives. "
        "Disk usage normally does not increase.",
        flush=True,
    )

    definition_candidates: list[Path] = []
    reference_files: list[str] = []
    changed_entry_sources = 0
    done_bytes = 0
    definition_pattern = re.compile(
        rb"(?m)^[ \t]*void[ \t]+sub_0092FAD0[ \t]*\([ \t]*void[ \t]*\)[ \t\r\n]*\{"
    )

    for index, (path, expected_size) in enumerate(zip(source_files, sizes), 1):
        before_pct = 100.0 if total_bytes == 0 else done_bytes * 100.0 / total_bytes
        print(
            f"[SCAN {index:02d}/{len(source_files):02d}] START "
            f"| {path.name} | {_fmt_bytes(expected_size)} "
            f"| global search: entry symbol + {SYMBOL} definition/reference "
            f"| total {before_pct:5.1f}% | elapsed {_fmt_time(time.perf_counter() - started)}",
            flush=True,
        )
        data = path.read_bytes()
        if b"sub_0092FAD0" in data:
            reference_files.append(path.name)
            if definition_pattern.search(data):
                definition_candidates.append(path)
        if generic in data:
            updated = data.replace(generic, public)
            if updated != data:
                path.write_bytes(updated)
                changed_entry_sources += 1
        done_bytes += expected_size
        _progress(index, len(source_files), done_bytes, total_bytes, path, started)

    if len(definition_candidates) != 1:
        if not definition_candidates:
            stub_hint = ""
            if "recomp_stubs_unresolved.c" in reference_files:
                stub_hint = " The symbol occurs in recomp_stubs_unresolved.c; inspect whether it is an exact generated unresolved placeholder."
            raise SystemExit(
                f"{SYMBOL} was referenced in {len(reference_files)} generated file(s), "
                "but no function definition was found anywhere in the generated tree. "
                "The validator searched all chunks before stopping." + stub_hint
            )
        raise SystemExit(
            f"Expected one global {SYMBOL} definition, found {len(definition_candidates)}: "
            + ", ".join(p.name for p in definition_candidates)
        )

    print("[STEP 4/5] Patching the unique global function definition...", flush=True)
    target_path = definition_candidates[0]
    raw = target_path.read_bytes()
    source_text = raw.decode("utf-8", errors="strict")
    source_text, found, location_kind = replace_guest_function_text(
        source_text, SYMBOL, target_path,
        allow_unresolved_stub=(target_path.name.lower() == "recomp_stubs_unresolved.c"),
    )
    if not found:
        raise SystemExit(f"Global definition candidate disappeared before patching: {target_path.name}.")
    encoded = source_text.encode("utf-8")
    if encoded != raw:
        target_path.write_bytes(encoded)

    print("[STEP 5/5] Verifying entry symbol, Lua redirect and obsolete-stub cleanup...", flush=True)
    for path in (header, dispatch):
        data = path.read_bytes()
        if generic in data:
            path.write_bytes(data.replace(generic, public))
    header_data = header.read_bytes()
    dispatch_data = dispatch.read_bytes()
    if public not in header_data or public not in dispatch_data:
        raise SystemExit("Debug entry symbol normalization did not complete correctly.")
    if generic in header_data or generic in dispatch_data:
        raise SystemExit("Generic debug entry symbol remains after normalization.")

    final_text = target_path.read_text(encoding="utf-8")
    if MARKER not in final_text or f"{MANUAL_SYMBOL}();" not in final_text:
        raise SystemExit("The manual Lua string-intern redirect did not survive verification.")
    if obsolete_stub.exists():
        obsolete_stub.unlink()
        print("[CLEANUP] Removed obsolete retail compatibility-stub source.", flush=True)

    elapsed = time.perf_counter() - started
    print(f"[OK] Debug entry 0x{entry:08X} normalized as xbe_entry_point.", flush=True)
    print(f"[OK] Updated {changed_entry_sources} generated entry-point source file(s).", flush=True)
    print(f"[OK] {SYMBOL} references found in {len(reference_files)} file(s); global definition located in {target_path.name}.", flush=True)
    if location_kind == "manual-implementation-replacement":
        print(f"[OK] Replaced only the exact unresolved-call placeholder with the reviewed {MANUAL_SYMBOL} implementation.", flush=True)
    else:
        print(f"[OK] Redirected the translated {SYMBOL} body to the reviewed {MANUAL_SYMBOL} implementation.", flush=True)
    print("[OK] No new generic compatibility stubs were generated; other unresolved calls remain visible to the linker/runtime checks.", flush=True)
    print(f"[DONE] Global validation finished in {_fmt_time(elapsed)} ({_fmt_bytes(total_bytes)} scanned).", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        raise SystemExit(1)
