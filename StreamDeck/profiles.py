#!/usr/bin/env python3
"""Builds the Stream Deck profiles the Knippi plugin ships (Michael 21.11.: "ein passendes Profil mit passenden Icons").

Format as Stream Deck's own export (measured by Gnotchi on the profile Elgato's Codex plugin ships): ZIP with `package.json`
and `Profiles/<UUID>.sdProfile/{manifest.json, Profiles/<page>/manifest.json}`. Fixed UUIDs, so every run gives the same file.
One page per device. Stream Deck + gets two dials (screenshots, video).

Run:  python3 -I StreamDeck/profiles.py StreamDeck/dev.mwlr.knippi.deck.sdPlugin/profiles
"""
import json
import sys
import uuid
import zipfile
from pathlib import Path

PLUGIN = {"Name": "Knippi", "UUID": "dev.mwlr.knippi.deck", "Version": "0.0.0.0"}   # set from argv[2] by build.sh
NS = uuid.UUID("6a1c2f8e-3b47-4d9a-9e0c-7f5b1d2a4c63")   # namespace for fixed UUIDs
STAMP = (2026, 11, 21, 0, 0, 0)


def fixed(name):
    return str(uuid.uuid5(NS, name))


TITLES = {"area": "Bereich", "window": "Fenster", "fullscreen": "Vollbild", "scrolling": "Scrollen", "last-area": "Wiederholen",
          "ocr": "Text", "color": "Farbe", "self-timer": "Timer", "record-area": "Video", "record-fullscreen": "Video voll"}


def key(slot, cmd):
    return {"ActionID": fixed(f"{slot}-{cmd}"), "LinkedTitle": True, "Name": TITLES[cmd], "Plugin": PLUGIN, "Resources": None,
            "Settings": {}, "State": 0,
            "States": [{"FontFamily": "", "FontSize": 10, "FontStyle": "", "FontUnderline": False, "OutlineThickness": 2,
                        "ShowTitle": True, "Title": TITLES[cmd], "TitleAlignment": "top", "TitleColor": "#ffffff"}],
            "UUID": f"dev.mwlr.knippi.deck.{cmd}"}


def dial(slot, lst):
    return {"ActionID": fixed(f"{slot}-dial-{lst}"), "LinkedTitle": True, "Name": "Regler", "Plugin": PLUGIN, "Resources": None,
            "Settings": {"list": lst, "index": 0}, "State": 0, "States": [{}], "UUID": "dev.mwlr.knippi.deck.dial"}


def grid(prefix, rows):
    return {f"{c},{r}": key(f"{prefix}{c}{r}", cmd) for r, row in enumerate(rows) for c, cmd in enumerate(row) if cmd}


# Device models measured 21.11. in Michael's ProfilesV3 (Mac mini): + = 20GBD9901, Neo = 20GBJ9901, MK.2 (15 keys) = 20GBL9901.
PROFILES = [
    {"file": "knippi-plus", "model": "20GBD9901", "second": "Encoder",
     "pages": [("Knippi", grid("p", [["area", "window", "fullscreen", "scrolling"], ["last-area", "ocr", "color", "self-timer"]]),
                {"0,0": dial("pd0", "shot"), "1,0": dial("pd1", "video")})]},
    {"file": "knippi-neo", "model": "20GBJ9901", "second": "Neo",
     "pages": [("Knippi", grid("n", [["area", "window", "fullscreen", "scrolling"], ["ocr", "color", "record-area", "record-fullscreen"]]),
                None)]},
    {"file": "knippi-mk2", "model": "20GBL9901", "second": None,
     "pages": [("Knippi", grid("m", [["area", "window", "fullscreen", "scrolling", "last-area"],
                                      ["ocr", "color", "self-timer", "record-area", "record-fullscreen"]]), None)]},
]


def build(p, target: Path):
    prof = fixed(p["file"] + "-profile").upper()
    pages = [fixed(f"{p['file']}-page-{i}") for i in range(len(p["pages"]))]
    default = fixed(p["file"] + "-default")
    manifest = {"Device": {"Model": p["model"], "UUID": fixed(p["file"] + "-device")}, "Name": "Knippi",
                "Pages": {"Current": "00000000-0000-0000-0000-000000000000", "Default": default, "Pages": pages},
                "Version": "3.0"}
    second = [{"Actions": None, "Type": p["second"]}] if p["second"] else []
    default_manifest = {"Controllers": [{"Actions": None, "Type": "Keypad"}] + second,
                        "Icon": "", "Name": ""}
    package = {"AppVersion": "7.6.1.23033", "DeviceModel": p["model"], "DeviceSettings": None, "FormatVersion": 1,
               "OSType": "macOS", "OSVersion": "27.2", "RequiredPlugins": [PLUGIN["UUID"]]}
    root = f"Profiles/{prof}.sdProfile"
    path = target / f"{p['file']}.streamDeckProfile"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        def add(name, obj):
            z.writestr(zipfile.ZipInfo(name, date_time=STAMP), json.dumps(obj, ensure_ascii=False, indent=2))

        def folder(name):
            z.writestr(zipfile.ZipInfo(name + "/", date_time=STAMP), "")

        add("package.json", package)
        folder("Profiles")
        folder(root)
        add(f"{root}/manifest.json", manifest)
        folder(f"{root}/Profiles")
        for page, (name, keys, second) in zip(pages, p["pages"]):
            folder(f"{root}/Profiles/{page.upper()}")
            add(f"{root}/Profiles/{page.upper()}/manifest.json",
                {"Controllers": [{"Actions": keys, "Type": "Keypad"}] + ([{"Actions": second, "Type": p["second"]}] if p["second"] else []),
                 "Icon": "", "Name": name})
        folder(f"{root}/Profiles/{default.upper()}")
        add(f"{root}/Profiles/{default.upper()}/manifest.json", default_manifest)
    return path


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if len(sys.argv) > 2:
        PLUGIN["Version"] = sys.argv[2]
    target.mkdir(parents=True, exist_ok=True)
    for p in PROFILES:
        print("written:", build(p, target))
