# /// script
# requires-python = ">=3.12"
# dependencies = ["cryptography>=43"]
# ///
"""Adds Google (with live suggestions) as the default search engine to every Ungoogled Chromium
profile, plus the site-search shortcuts yt / gh / maps and any missing @bookmarks / @history / @tabs.

Run through Set-Search-Engine.ps1, which closes and reopens the browser. The browser MUST be closed.

Why this is needed: Ungoogled Chromium ships without a Google entry (its built-in slot 1 is
"No Search"), entries added in Settings never get a suggestion URL, and the DefaultSearchProvider
policies are blocked on PCs that are not domain-joined. So the entry is written straight into each
profile's "Web Data" database. Chromium (Windows) checks every row against an encrypted checksum:
    url_hash = os_crypt( 0x02 + SHA-256( Pickle(id:int64, url:str, keyword:str16,
                                                enforced_by_policy:bool, starter_pack_id:int) ) )
(components/search_engines/template_url_data.cc, GenerateHash). Rows with a wrong checksum are
deleted by the browser on start, so a mistake here costs nothing but the new row.

Every changed file is backed up first as "<file>.before-search-<date>".
"""

import ctypes
import ctypes.wintypes as wt
import base64
import hashlib
import json
import os
import shutil
import sqlite3
import struct
import sys
import time
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

USER_DATA = Path(os.environ.get("CHROMIUM_USER_DATA") or Path(os.environ["LOCALAPPDATA"]) / "Chromium" / "User Data")
STAMP = time.strftime("%Y%m%d-%H%M")

GOOGLE_GUID = "7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e01"
ENGINES = [
    # sync_guid, name, keyword, url, suggest_url, favicon
    (GOOGLE_GUID, "Google", "google.com",
     "https://www.google.com/search?q={searchTerms}&ie={inputEncoding}",
     "https://www.google.com/complete/search?client=chrome&q={searchTerms}",
     "https://www.google.com/favicon.ico"),
    ("7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e02", "YouTube", "yt",
     "https://www.youtube.com/results?search_query={searchTerms}", "",
     "https://www.youtube.com/favicon.ico"),
    ("7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e03", "GitHub", "gh",
     "https://github.com/search?q={searchTerms}", "",
     "https://github.com/favicon.ico"),
    ("7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e04", "Google Maps", "maps",
     "https://www.google.com/maps/search/{searchTerms}", "",
     "https://www.google.com/images/branding/product/ico/web_maps_icon_32dp.ico"),
]
OUR_KEYWORDS = [e[2] for e in ENGINES]
OUR_GUIDS = [e[0] for e in ENGINES]
STARTER_PACK = {  # starter_pack_id: (sync_guid, name, keyword, url)
    1: ("ec205736-edd7-4022-a9a3-b431fc000001", "Bookmarks", "@bookmarks", "chrome://bookmarks/?q={searchTerms}"),
    2: ("ec205736-edd7-4022-a9a3-b431fc000002", "History", "@history", "chrome://history/?q={searchTerms}"),
    3: ("ec205736-edd7-4022-a9a3-b431fc000003", "Tabs", "@tabs", "chrome://tabs/?q={searchTerms}"),
}


# ---------- os_crypt key (DPAPI-wrapped AES-256 key in Local State) ----------
class _Blob(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def dpapi_unprotect(data: bytes) -> bytes:
    src = _Blob(len(data), ctypes.cast(ctypes.create_string_buffer(data, len(data)), ctypes.POINTER(ctypes.c_char)))
    out = _Blob()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(src), None, None, None, None, 0, ctypes.byref(out)):
        raise OSError("DPAPI could not unwrap the browser key (run as the same Windows user).")
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out.pbData)


def load_key(local_state: dict) -> bytes:
    wrapped = base64.b64decode(local_state["os_crypt"]["encrypted_key"])
    if not wrapped.startswith(b"DPAPI"):
        raise SystemExit("Unexpected key format in Local State.")
    return dpapi_unprotect(wrapped[5:])


# ---------- checksum ----------
def _pad4(b: bytes) -> bytes:
    return b + b"\0" * (-len(b) % 4)


def url_hash(key: bytes, row_id: int, url: str, keyword: str, enforced: bool, starter_pack_id: int) -> bytes:
    u, k = url.encode("utf-8"), keyword.encode("utf-16-le")
    body = (struct.pack("<q", row_id)
            + struct.pack("<i", len(u)) + _pad4(u)
            + struct.pack("<i", len(keyword)) + _pad4(k)
            + struct.pack("<i", int(enforced)) + struct.pack("<i", starter_pack_id))
    plain = b"\x02" + hashlib.sha256(struct.pack("<I", len(body)) + body).digest()
    nonce = os.urandom(12)
    return b"v10" + nonce + AESGCM(key).encrypt(nonce, plain, None)


def check_hash(key: bytes, row) -> bool:
    row_id, url, keyword, enforced, starter, blob = row
    if not blob or blob[:3] != b"v10":
        return False
    plain = AESGCM(key).decrypt(blob[3:15], blob[15:], None)
    u, k = url.encode("utf-8"), keyword.encode("utf-16-le")
    body = (struct.pack("<q", row_id) + struct.pack("<i", len(u)) + _pad4(u)
            + struct.pack("<i", len(keyword)) + _pad4(k)
            + struct.pack("<i", int(enforced)) + struct.pack("<i", starter))
    return plain == b"\x02" + hashlib.sha256(struct.pack("<I", len(body)) + body).digest()


def now_chrome() -> int:  # microseconds since 1601-01-01
    return int((time.time() + 11644473600) * 1_000_000)


def backup(p: Path) -> None:
    if p.exists():
        shutil.copy2(p, p.with_name(f"{p.name}.before-search-{STAMP}"))


# ---------- per profile ----------
def fix_profile(key: bytes, folder: Path) -> str:
    web_data, prefs_path = folder / "Web Data", folder / "Preferences"
    if not web_data.exists() or not prefs_path.exists():
        return "skipped (no Web Data / Preferences yet)"
    backup(web_data)
    backup(prefs_path)

    con = sqlite3.connect(web_data)
    try:
        cur = con.cursor()
        # The checksum must still match the code above for an existing row, or the recipe changed.
        sample = cur.execute("select id,url,keyword,enforced_by_policy,starter_pack_id,url_hash from keywords "
                             "where url_hash is not null limit 1").fetchone()
        if sample and not check_hash(key, sample):
            raise SystemExit(f"{folder.name}: existing checksum does not match the known recipe - "
                             "Chromium changed it; nothing written.")

        removed = cur.execute(
            f"delete from keywords where keyword in ({','.join('?' * len(OUR_KEYWORDS))}) "
            f"or sync_guid in ({','.join('?' * len(OUR_GUIDS))}) "
            "or (url = 'https://www.google.com/' and prepopulate_id = 0)",  # broken hand-made entry
            OUR_KEYWORDS + OUR_GUIDS).rowcount

        cols = [r[1] for r in cur.execute("pragma table_info(keywords)")]
        next_id = (cur.execute("select max(id) from keywords").fetchone()[0] or 0) + 1
        ts = now_chrome()

        def insert(guid, name, keyword, url, suggest, favicon, starter=0):
            nonlocal next_id
            row = dict.fromkeys(cols, "")
            row.update(id=next_id, short_name=name, keyword=keyword, favicon_url=favicon, url=url,
                       safe_for_autoreplace=0, originating_url="", date_created=ts, usage_count=0,
                       input_encodings="UTF-8", suggest_url=suggest, prepopulate_id=0, created_by_policy=0,
                       last_modified=ts, sync_guid=guid, alternate_urls="[]", last_visited=0,
                       created_from_play_api=0, is_active=1, starter_pack_id=starter,
                       enforced_by_policy=0, featured_by_policy=0,
                       url_hash=url_hash(key, next_id, url, keyword, False, starter))
            cur.execute(f"insert into keywords ({','.join(cols)}) values ({','.join('?' * len(cols))})",
                        [row[c] for c in cols])
            next_id += 1

        for guid, name, keyword, url, suggest, favicon in ENGINES:
            insert(guid, name, keyword, url, suggest, favicon)

        have = {r[0] for r in cur.execute("select starter_pack_id from keywords where starter_pack_id > 0")}
        added_sp = []
        for sp_id, (guid, name, keyword, url) in STARTER_PACK.items():
            if sp_id not in have:
                insert(guid, name, keyword, url, "", "", starter=sp_id)
                added_sp.append(keyword)
        con.commit()
    finally:
        con.close()

    prefs = json.loads(prefs_path.read_text(encoding="utf-8"))
    dsp = prefs.setdefault("default_search_provider", {})
    dsp["guid"] = GOOGLE_GUID
    dsp["enabled"] = True
    prefs.setdefault("default_search_provider_data", {}).pop("template_url_data", None)
    prefs.setdefault("search", {})["suggest_enabled"] = True
    prefs.setdefault("profile", {})["exit_type"] = "Normal"
    prefs_path.write_text(json.dumps(prefs, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")

    note = f"Google default + yt/gh/maps"
    if added_sp:
        note += f" + {' '.join(added_sp)}"
    if removed:
        note += f" (replaced {removed} old row(s))"
    return note


def main() -> None:
    local_state = json.loads((USER_DATA / "Local State").read_text(encoding="utf-8"))
    key = load_key(local_state)
    profiles = local_state["profile"]["info_cache"]
    for folder_name, info in profiles.items():
        result = fix_profile(key, USER_DATA / folder_name)
        print(f"  {folder_name:<11} {info.get('name', ''):<45} {result}")


if __name__ == "__main__":
    sys.exit(main())
