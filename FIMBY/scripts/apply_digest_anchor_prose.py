"""Apply digest anchor Body__c and field updates from the approved plan markdown."""
from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

PLAN_PATH = Path(
    r"C:\Users\srathjen\.cursor\projects\c-Users-srathjen-FIMBY\uploads"
    r"\digest_anchor_prose_8ce512e3.plan-L1-L374-0.md"
)
CMDT_DIR = Path(__file__).resolve().parents[1] / "force-app/main/default/customMetadata"
NS = {
    "m": "http://soap.sforce.com/2006/04/metadata",
    "xsi": "http://www.w3.org/2001/XMLSchema-instance",
    "xsd": "http://www.w3.org/2001/XMLSchema-instance",
}

# Plan bullet key -> CMDT developer suffix (without FIMBY_Digest_Anchor. prefix)
PLAN_KEY_TO_DEV: dict[str, str] = {
    "Jan 1, Emancipation Proclamation": "OTD_Jan01_Emancipation_Proclamation",
    "Jan 27, Holocaust remembrance": "OTD_Jan27_Holocaust_Remembrance",
    "Feb 8, Martin Buber": "OTD_Feb08_Martin_Buber",
    "Mar 8, International Women's Day": "OTD_Mar08_Intl_Womens_Day",
    "Mar 10, Harriet Tubman": "OTD_Mar10_Harriet_Tubman",
    "Mar 21, Anti-racism day": "OTD_Mar21_Anti_Racism_Day",
    "Mar 25, Triangle Shirtwaist Fire": "OTD_Mar25_Triangle_Shirtwaist_Fire",
    "Apr 9, Dietrich Bonhoeffer": "OTD_Apr09_Bonhoeffer",
    "Apr 11, Simone Weil": "OTD_Apr11_Simone_Weil",
    "Apr 22, Earth Day": "OTD_Apr22_Earth_Day",
    "Apr 28, Harper Lee": "OTD_Apr28_Harper_Lee",
    "May 8, V-E Day": "OTD_May08_VE_Day",
    "May 30, Memorial Day": "OTD_May30_Memorial_Day",
    "Jun 12, Anne Frank": "OTD_Jun12_Anne_Frank",
    "Jun 15, Magna Carta": "OTD_Jun15_Magna_Carta",
    "Jun 19, Juneteenth": "OTD_Jun19_Juneteenth",
    "Jun 20, World Refugee Day": "OTD_Jun20_World_Refugee_Day",
    "Jun 24, John the Baptist": "OTD_Jun24_John_The_Baptist",
    "Aug 23, Slave Trade remembrance": "OTD_Aug23_Slave_Trade_Remembrance",
    "Sep 8, Literacy Day": "OTD_Sep08_Literacy_Day",
    "Sep 12, Steve Biko": "OTD_Sep12_Steve_Biko",
    "Oct 10, World Mental Health Day": "OTD_Oct10_Mental_Health_Day",
    "Oct 16, World Food Day": "OTD_Oct16_World_Food_Day",
    "Oct 24, United Nations Day": "OTD_Oct24_United_Nations_Day",
    "Nov 7, Albert Camus": "OTD_Nov07_Albert_Camus",
    "Nov 11, Remembrance Day": "OTD_Nov11_Remembrance_Day",
    "Nov 20, Rights of the Child": "OTD_Nov20_Rights_Of_Child",
    "Nov 25, Violence against women": "OTD_Nov25_Violence_Against_Women",
    "Dec 1, Rosa Parks": "OTD_Dec01_Rosa_Parks",
    "Dec 3, Persons with Disabilities": "OTD_Dec03_Disability_Day",
    "Dec 10, Human Rights Day": "OTD_Dec10_Human_Rights_Day",
    "Dec 18, International Migrants Day": "OTD_Dec18_Migrants_Day",
    "Devotional D-3": "REF_D_03",
    "Devotional D-4": "REF_D_04",
    "May 15, Peter Maurin": "OTD_May15_Peter_Maurin",
    "May 25, Venerable Bede": "OTD_May25_Venerable_Bede",
    "Jun 26, UN Charter signed": "OTD_Jun26_UN_Charter",
    "Sep 11": "OTD_Sep11_Sept_11",
    "Nov 22, C.S. Lewis": "OTD_Nov22_CS_Lewis",
    "Jan 3, Tolkien": "OTD_Jan03_JRR_Tolkien",
    "Jan 5, George Washington Carver": "OTD_Jan05_George_Washington_Carver",
    "Jan 15 (was Jan 10), Etty Hillesum": "OTD_Jan10_Etty_Hillesum",
    "Jan 22, Thich Nhat Hanh": "OTD_Jan22_Thich_Nhat_Hanh",
    "Feb 1, St. Brigid": "OTD_Feb01_St_Brigid",
    "Jul 17 (was Feb 5), Dorothea Dix": "OTD_Feb05_Dorothea_Dix",
    "Feb 7, Viola Desmond": "OTD_Feb07_Viola_Desmond",
    "Feb 9, Baba Amte": "OTD_Feb09_Baba_Amte",
    "Feb 11, Mandela released": "OTD_Feb11_Mandela_Released",
    "Feb 14, Women's Memorial March": "OTD_Feb14_Womens_Memorial_March",
    "Feb 19, Mister Rogers' Neighborhood premiered": "OTD_Feb19_Mr_Rogers_Premiered",
    "Feb 20, Frederick Douglass": "OTD_Feb20_Frederick_Douglass",
    "Mar 11, Friedrich Raiffeisen": "OTD_Mar11_Raiffeisen",
    "Mar 19, St. Joseph": "OTD_Mar19_St_Joseph",
    "Mar 20, Mr. Rogers": "OTD_Mar20_Mr_Rogers",
    "Mar 24, Oscar Romero": "OTD_Mar24_Oscar_Romero",
    "Apr 4, Martin Luther King Jr": "OTD_Apr04_MLK",
    "Apr 10, Howard Thurman": "OTD_Apr10_Howard_Thurman",
    "Apr 12, Terry Fox began": "OTD_Apr12_Terry_Fox_Began",
    "Apr 14, Mondragon": "OTD_Apr14_Mondragon_Founded",
    "Apr 15, Corrie ten Boom": "OTD_Apr15_Corrie_ten_Boom",
    "Apr 23, Toyohiko Kagawa": "OTD_Apr23_Toyohiko_Kagawa",
    "Apr 26, Rosemary Brown": "OTD_Apr26_Rosemary_Brown",
    "Apr 29, Catherine of Siena": "OTD_Apr29_Catherine_Of_Siena",
    "May 1, Catholic Worker": "OTD_May01_Catholic_Worker",
    "May 2, Paulo Freire": "OTD_May02_Paulo_Freire",
    "May 4, Jane Jacobs": "OTD_May04_Jane_Jacobs",
    "May 5, Kierkegaard": "OTD_May05_Kierkegaard",
    "May 12, Florence Nightingale": "OTD_May12_Florence_Nightingale",
    "May 21, Jane Addams": "OTD_May21_Jane_Addams",
    "Jun 3, Pope John XXIII": "OTD_Jun03_John_XXIII",
    "Jun 5, André Trocmé": "OTD_Jun05_Andre_Trocme",
    "Jun 8 (was Jun 10), Gustavo Gutiérrez": "OTD_Jun10_Gutierrez",
    "Jun 28, Terry Fox": "OTD_Jun28_Terry_Fox",
    "Jun 29, Peter and Paul": "OTD_Jun29_Peter_And_Paul",
    "Jul 8, Abdul Sattar Edhi": "OTD_Jul08_Edhi",
    "Jul 11, St. Benedict": "OTD_Jul11_St_Benedict",
    "Jul 14, Bastille Day": "OTD_Jul14_Bastille_Day",
    "Jul 22, Mary Magdalene": "OTD_Jul22_Mary_Magdalene",
    "Jul 29, Wilberforce": "OTD_Jul29_Wilberforce",
    "Aug 4, Raoul Wallenberg": "OTD_Aug04_Wallenberg",
    "Aug 5, Wendell Berry": "OTD_Aug05_Wendell_Berry",
    "Aug 6, Hiroshima": "OTD_Aug06_Hiroshima",
    "Aug 10, St. Lawrence": "OTD_Aug10_St_Lawrence",
    'Aug 28, "I Have a Dream"': "OTD_Aug28_I_Have_A_Dream",
    "Sep 4, E.F. Schumacher": "OTD_Sep04_Schumacher",
    "Sep 7, Ela Bhatt": "OTD_Sep07_Ela_Bhatt",
    "Sep 18, Hull House": "OTD_Sep18_Hull_House",
    "Sep 21, Henri Nouwen": "OTD_Sep21_Henri_Nouwen",
    "Sep 22, Guru Nanak": "OTD_Sep22_Guru_Nanak",
    "Sep 23, Chief Dan George": "OTD_Sep23_Chief_Dan_George",
    "Sep 25, Wangari Maathai": "OTD_Sep25_Wangari_Maathai",
    "Sep 27, St. Vincent de Paul": "OTD_Sep27_Vincent_de_Paul",
    "Sep 30, Truth and Reconciliation": "OTD_Sep30_Truth_And_Reconciliation",
    "Oct 1, Thérèse of Lisieux": "OTD_Oct01_Therese_Of_Lisieux",
    "Oct 4, St. Francis": "OTD_Oct04_Francis_Of_Assisi",
    "Oct 5, Václav Havel": "OTD_Oct05_Vaclav_Havel",
    "Oct 11, Eleanor Roosevelt": "OTD_Oct11_Eleanor_Roosevelt",
    "Oct 15, St. Teresa of Avila": "OTD_Oct15_Teresa_Of_Avila",
    "Oct 17, Eradication of Poverty": "OTD_Oct17_Eradication_Of_Poverty",
    "Oct 18, St. Luke": "OTD_Oct18_St_Luke",
    "Oct 21, Ursula K. Le Guin": "OTD_Oct21_Le_Guin",
    "Oct 31, Alphonse Desjardins": "OTD_Oct31_Desjardins",
    "Nov 2, All Souls": "OTD_Nov02_All_Souls_Day",
    "Nov 4, Murray Sinclair": "OTD_Nov04_Murray_Sinclair",
    "Nov 10, Ken Saro-Wiwa": "OTD_Nov10_Saro_Wiwa",
    "Nov 15, Vinoba Bhave": "OTD_Nov15_Vinoba_Bhave",
    "Nov 29, Dorothy Day": "OTD_Nov29_Dorothy_Day",
    "Dec 5, Nelson Mandela": "OTD_Dec05_Mandela",
    "Dec 6, B.R. Ambedkar": "OTD_Dec06_Ambedkar",
    "Dec 14, Catherine Doherty": "OTD_Dec14_Catherine_Doherty",
    "Dec 15, TRC final report": "OTD_Dec15_TRC_Final_Report",
    "Dec 17, Rumi": "OTD_Dec17_Rumi",
    "Dec 21, Rochdale Pioneers": "OTD_Dec21_Rochdale_Pioneers",
    "Dec 26, Desmond Tutu": "OTD_Dec26_Desmond_Tutu",
    "Dec 31, New Year's Eve": "OTD_Dec31_New_Years_Eve",
    "Diwali": "OBS_Diwali",
    "Mid-Autumn Festival": "OBS_Mid_Autumn_Festival",
    "Sukkot": "OBS_Sukkot",
    "D-1": "REF_D_01",
    "D-2": "REF_D_02",
    "D-5": "REF_D_05",
    "D-6": "REF_D_06",
    "D-7": "REF_D_07",
    "NT-1": "REF_NT_01",
    "NT-2": "REF_NT_02",
    "NT-3": "REF_NT_03",
    "NT-4": "REF_NT_04",
    "NT-5": "REF_NT_05",
    "NT-6": "REF_NT_06",
    "NT-7": "REF_NT_07",
    "HT-1": "REF_HT_01",
    "HT-2": "REF_HT_02",
    "HT-3": "REF_HT_03",
    "HT-5": "REF_HT_05",
    "HT-6": "REF_HT_06",
    "R-1": "REF_R_01",
    "R-2": "REF_R_02",
    "R-3": "REF_R_03",
    "R-4": "REF_R_04",
    "R-5": "REF_R_05",
    "R-6": "REF_R_06",
    "R-7": "REF_R_07",
}

FIELD_UPDATES: dict[str, dict] = {
    "OTD_Jan10_Etty_Hillesum": {"day": 15, "month": 1},
    "OTD_Feb05_Dorothea_Dix": {"day": 17, "month": 7},
    "OTD_Apr11_Simone_Weil": {"day": 24, "month": 8},
    "OTD_Jun10_Gutierrez": {"day": 8, "month": 6},
    "OTD_Feb20_Frederick_Douglass": {"type": "Death"},
    "OTD_Oct11_Eleanor_Roosevelt": {"type": "Birth"},
    "OTD_Aug04_Wallenberg": {"type": "Birth", "title": "Raoul Wallenberg"},
    "OTD_May25_Venerable_Bede": {"type": "Feast_Day"},
    "OTD_Dec01_Rosa_Parks": {"type": "Event", "subtitle": "1955"},
    "OTD_Aug05_Wendell_Berry": {"subtitle": "1934–2026"},
    "OTD_Mar11_Raiffeisen": {"subtitle": "1818–1888"},
    "OTD_Oct16_World_Food_Day": {"subtitle": "1981"},
}


def parse_plan_bodies(text: str) -> dict[str, str]:
    bodies: dict[str, str] = {}
    current_key: str | None = None

    for line in text.splitlines():
        stripped = line.strip()

        m_prop = re.match(r"^Proposed:\s*(.+)$", stripped)
        if m_prop and current_key:
            bodies[current_key] = m_prop.group(1).strip()
            continue

        m_header = re.match(r"^\*\*(.+?)\*\*", stripped)
        if m_header and not stripped.startswith("- "):
            current_key = m_header.group(1).strip().rstrip(".")
            continue

        m_bullet = re.match(r"^- \*\*(.+?)\*\*\.?\s*(.*)$", stripped)
        if m_bullet:
            key = m_bullet.group(1).strip().rstrip(".")
            rest = m_bullet.group(2).strip()
            current_key = key
            if rest and rest.lower() != "rewritten above.":
                bodies[key] = rest
            continue

        if stripped.startswith("**") and "Now:" in stripped:
            m = re.match(r"^\*\*(.+?)\*\*", stripped)
            if m:
                current_key = m.group(1).strip()

    return bodies


def xml_escape_body(body: str) -> str:
    return (
        body.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def set_field_value(root: ET.Element, field_name: str, value) -> None:
    for values in root.findall("m:values", NS):
        fld = values.find("m:field", NS)
        if fld is not None and fld.text == field_name:
            val_el = values.find("m:value", NS)
            if value is None:
                if val_el is not None:
                    val_el.set(f"{{{NS['xsi']}}}type", "xsd:string")
                    val_el.text = None
                    for attr in list(val_el.attrib):
                        if "nil" in attr:
                            del val_el.attrib[attr]
                    val_el.set(f"{{{NS['xsi']}}}nil", "true")
            elif isinstance(value, float):
                if val_el is None:
                    val_el = ET.SubElement(values, f"{{{NS['m']}}}value")
                val_el.set(f"{{{NS['xsi']}}}type", "xsd:double")
                val_el.text = f"{value:.1f}" if value == int(value) else str(value)
                for attr in list(val_el.attrib):
                    if "nil" in attr:
                        del val_el.attrib[attr]
            else:
                if val_el is None:
                    val_el = ET.SubElement(values, f"{{{NS['m']}}}value")
                val_el.set(f"{{{NS['xsi']}}}type", "xsd:string")
                val_el.text = str(value)
                for attr in list(val_el.attrib):
                    if "nil" in attr:
                        del val_el.attrib[attr]


def apply() -> None:
    plan_text = PLAN_PATH.read_text(encoding="utf-8")
    plan_bodies = parse_plan_bodies(plan_text)
    dev_bodies: dict[str, str] = {}
    missing_keys: list[str] = []

    for plan_key, dev in PLAN_KEY_TO_DEV.items():
        body = plan_bodies.get(plan_key)
        if not body:
            missing_keys.append(plan_key)
            continue
        dev_bodies[dev] = body

    if missing_keys:
        raise SystemExit(f"Missing plan bodies for keys: {missing_keys[:10]} ... ({len(missing_keys)} total)")

    updated = 0
    for dev, body in dev_bodies.items():
        path = CMDT_DIR / f"FIMBY_Digest_Anchor.{dev}.md-meta.xml"
        if not path.exists():
            raise SystemExit(f"Missing file: {path}")

        tree = ET.parse(path)
        root = tree.getroot()
        set_field_value(root, "Body__c", body)

        fields = FIELD_UPDATES.get(dev, {})
        if "day" in fields:
            set_field_value(root, "Day__c", float(fields["day"]))
        if "month" in fields:
            set_field_value(root, "Month__c", float(fields["month"]))
        if "type" in fields:
            set_field_value(root, "Type__c", fields["type"])
        if "subtitle" in fields:
            set_field_value(root, "Subtitle__c", fields["subtitle"])
        if "title" in fields:
            set_field_value(root, "Title__c", fields["title"])

        ET.register_namespace("", NS["m"])
        ET.register_namespace("xsi", NS["xsi"])
        tree.write(path, encoding="UTF-8", xml_declaration=True)
        updated += 1

    print(f"Updated {updated} digest anchor records.")


if __name__ == "__main__":
    apply()
