#!/usr/bin/env python3
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
"""Local checks for site/: ids/anchors, relative links and assets exist, no empty href, no <script>, no personal paths,
images have alt, same section ids in every language, download is either inactive or points to the configured asset URL."""
import pathlib, re, sys
from html.parser import HTMLParser
S = pathlib.Path(__file__).resolve().parent.parent / "site"
errs = []
class P(HTMLParser):
    def __init__(s): super().__init__(); s.ids=set(); s.links=[]; s.imgs=[]; s.scripts=0; s.btnoff=0; s.sections=[]
    def handle_starttag(s, t, a):
        a = dict(a)
        if "id" in a: s.ids.add(a["id"])
        if t == "a": s.links.append(a.get("href"))
        if t == "img": s.imgs.append(a)
        if t == "script": s.scripts += 1
        if t == "section": s.sections.append(a.get("id"))
        if "btn off" in (a.get("class") or ""): s.btnoff += 1
pages = {"en": S/"index.html", "ro": S/"ro"/"index.html", "es": S/"es"/"index.html"}
secs = {}
for code, f in pages.items():
    txt = f.read_text(encoding="utf-8"); p = P(); p.feed(txt); secs[code] = p.sections
    if p.scripts: errs.append(f"{code}: <script> present")
    if re.search(r"does not connect to the internet|does not collect data|nu se conectează la internet|nu colectează date|no se conecta a internet|ni recopila datos|without workarounds|fără ocolișuri|sin rodeos|There is no network access|no update check|fără verificare de actualizări|sin comprobación de actualizaciones|no self-updater", txt, re.I): errs.append(f"{code}: absolute privacy/Gatekeeper claim")
    if not p.btnoff and "releases/download/v" not in txt: errs.append(f"{code}: primary download should use the versioned asset")
    if re.search(r"/Users/|/Volumes/|gordasgdc@|academiagdc", txt): errs.append(f"{code}: personal data")
    for h in p.links:
        if h is None or h == "": errs.append(f"{code}: empty href"); continue
        if h.startswith("#"):
            if h[1:] not in p.ids: errs.append(f"{code}: dangling anchor {h}")
        elif not h.startswith("http"):
            if not (f.parent / h).resolve().exists() and not (f.parent / h / "index.html").exists(): errs.append(f"{code}: broken relative link {h}")
        elif "releases/latest/download" in h and p.btnoff: errs.append(f"{code}: active download link while preview state is on")
    for i in p.imgs:
        if i.get("alt") is None: errs.append(f"{code}: img without alt {i.get('src')}")
        if i.get("src") and not i["src"].startswith("http") and not (f.parent / i["src"]).exists(): errs.append(f"{code}: missing asset {i['src']}")
    if "lang=\"" + code + "\"" not in txt: errs.append(f"{code}: wrong lang attribute")
    if not p.btnoff and "releases/latest/download" not in txt: errs.append(f"{code}: no download state")
if len({tuple(v) for v in secs.values()}) != 1: errs.append(f"section ids differ across languages: {secs}")
print("site OK" if not errs else "\n".join("FAIL " + e for e in errs)); sys.exit(1 if errs else 0)
