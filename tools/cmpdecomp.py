#!/usr/bin/env python3
"""Compare two decompilation dumps, function by function.

Addresses and auto-names are normalized before the diff.

Usage:
  cmpdecomp.py a.c b.c [--show <name-substring>]
"""

from __future__ import annotations

import difflib
import re
import sys

_ADDR = re.compile(
    r"\b(?:0x)?7[fF]{2}[0-9A-Fa-f]{6,}\b|"
    r"\b(?:sub|loc|unk|byte|word|dword|qword|off|stru|asc|locret)_[0-9A-Fa-f]+\b|"
    r"\bLABEL_\d+\b"
)


def load(path: str) -> dict[str, str]:
    """Load a decompilation dump keyed by function name.

    Args:
      path: Path to a dump whose functions start with `//==== 0x... name`.

    Returns:
      Mapping of function name to source text.
    """
    funcs: dict[str, str] = {}
    name: str | None = None
    buf: list[str] = []
    with open(path, errors="ignore") as handle:
        for line in handle:
            match = re.match(r"//==== (0x[0-9a-f]+) (\S+)", line)
            if match:
                if name:
                    funcs[name] = "".join(buf)
                name = demangle_key(match.group(2))
                buf = []
            else:
                buf.append(line)
    if name:
        funcs[name] = "".join(buf)
    return funcs


def demangle_key(name: str) -> str:
    """Return the dump's function name unchanged."""
    return name


def norm(text: str) -> str:
    """Normalize addresses, comments, and register names for comparison."""
    text = _ADDR.sub("ADDR", text)
    text = re.sub(r"//.*", "", text)
    text = re.sub(r"\b[av]\d+\b", "V", text)  # register/variable numbering
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def main(argv: list[str] | None = None) -> None:
    """Compare two dumps listed on the command line."""
    args = sys.argv if argv is None else argv
    left, right = load(args[1]), load(args[2])
    show = args[args.index("--show") + 1] if "--show" in args else None
    print(
        f"{len(left)} vs {len(right)} functions; only in A: "
        f"{sorted(set(left) - set(right))[:10]}; only in B: "
        f"{sorted(set(right) - set(left))[:10]}"
    )
    same: list[str] = []
    diff: list[str] = []
    for name in sorted(set(left) & set(right)):
        (same if norm(left[name]) == norm(right[name]) else diff).append(name)
    print(f"identical {len(same)}, different {len(diff)}")
    for name in diff:
        ratio = difflib.SequenceMatcher(
            None, norm(left[name]), norm(right[name]), autojunk=False
        ).quick_ratio()
        print(
            f"  {ratio:5.3f} {len(left[name]):6d}/{len(right[name]):6d} {name}"
        )
    if show:
        for name in diff:
            if show in name:
                print("=" * 20, name)
                left_lines = [
                    _ADDR.sub("ADDR", line.rstrip())
                    for line in left[name].splitlines()
                ]
                right_lines = [
                    _ADDR.sub("ADDR", line.rstrip())
                    for line in right[name].splitlines()
                ]
                for line in difflib.unified_diff(
                    left_lines, right_lines, "A", "B", lineterm="", n=1
                ):
                    print(line)


if __name__ == "__main__":
    main()
