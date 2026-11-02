"""Capitalize sentence starts on loading messages and seasonal theme titles (text-only)."""
from __future__ import annotations

import re
from pathlib import Path

CMDT_DIR = Path(__file__).resolve().parents[1] / "force-app/main/default/customMetadata"

PROPER_REPLACEMENTS = [
    (re.compile(r"\bcanada\b", re.I), "Canada"),
    (re.compile(r"\bchristmas\b", re.I), "Christmas"),
    (re.compile(r"\beaster\b", re.I), "Easter"),
    (re.compile(r"\bthanksgiving\b", re.I), "Thanksgiving"),
    (re.compile(r"\bvalentine's\b", re.I), "Valentine's"),
    (re.compile(r"\bjane's\b", re.I), "Jane's"),
    (re.compile(r"\badvent\b", re.I), "Advent"),
    (re.compile(r"\bepiphany\b", re.I), "Epiphany"),
    (re.compile(r"\bearth day\b", re.I), "Earth Day"),
    (re.compile(r"\bshakeout\b", re.I), "ShakeOut"),
    (re.compile(r"\bindigenous\b", re.I), "Indigenous"),
]


def capitalize_text(text: str, apply_proper: bool) -> str:
    if not text or not text[0].islower():
        return text
    out = text[0].upper() + text[1:]
    if apply_proper:
        for pattern, repl in PROPER_REPLACEMENTS:
            out = pattern.sub(repl, out)
    return out


def replace_field_value(text: str, field: str, apply_proper: bool) -> tuple[str, bool]:
    pattern = re.compile(
        rf"(<field>{field}</field>\s*<value xsi:type=\"xsd:string\">)(.*?)(</value>)",
        re.DOTALL,
    )

    def repl(match: re.Match) -> str:
        inner = match.group(2)
        new_inner = capitalize_text(inner, apply_proper)
        return match.group(1) + new_inner + match.group(3)

    new_text, count = pattern.subn(repl, text, count=1)
    return new_text, count > 0 and new_text != text


def main() -> None:
    n = 0
    for path in CMDT_DIR.glob("FIMBY_Loading_Message.Email_Intent_*.md-meta.xml"):
        text = path.read_text(encoding="utf-8")
        new_text, changed = replace_field_value(text, "Message__c", False)
        if changed:
            path.write_text(new_text, encoding="utf-8")
            n += 1
    for path in CMDT_DIR.glob("FIMBY_Seasonal_Theme.*.md-meta.xml"):
        text = path.read_text(encoding="utf-8")
        new_text, changed = replace_field_value(text, "Title__c", True)
        if changed:
            path.write_text(new_text, encoding="utf-8")
            n += 1
    print(f"Updated {n} CMDT files.")


if __name__ == "__main__":
    main()
