"""Restore Salesforce CMDT XML namespace declarations after ElementTree writes."""
from __future__ import annotations

import re
from pathlib import Path

CMDT_DIR = Path(__file__).resolve().parents[1] / "force-app/main/default/customMetadata"
ROOT_OPEN = (
    '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema">'
)


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text
    text = text.replace("ns0:", "")
    text = re.sub(r'\sxmlns:ns0="[^"]+"', "", text)
    text = text.replace("<?xml version='1.0' encoding='UTF-8'?>", '<?xml version="1.0" encoding="UTF-8"?>')
    text = re.sub(
        r"<CustomMetadata xmlns=\"http://soap\.sforce\.com/2006/04/metadata\" "
        r"xmlns:xsi=\"http://www\.w3\.org/2001/XMLSchema-instance\">",
        ROOT_OPEN,
        text,
        count=1,
    )
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> None:
    n = 0
    for pattern in ("FIMBY_Digest_Anchor.*", "FIMBY_Loading_Message.*", "FIMBY_Seasonal_Theme.*"):
        for path in CMDT_DIR.glob(pattern):
            if fix_file(path):
                n += 1
    print(f"Fixed {n} files.")


if __name__ == "__main__":
    main()
