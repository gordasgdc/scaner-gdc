#!/usr/bin/env python3
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
"""Verification fixture: writes ONE invented product record plus a generated gradient image into a storage root, so screenshots
can show the Product section without network access or any third-party image. Usage: seed-demo-product.py <storage-root> <product-key>"""
import hashlib, json, pathlib, struct, sys, zlib, datetime
root, key = pathlib.Path(sys.argv[1]), sys.argv[2]
w, h = 640, 360
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        rows += bytes((int(40 + 90 * x / w), int(70 + 100 * y / h), int(120 + 80 * (x + y) / (w + h))))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
name = hashlib.sha256(png).hexdigest() + ".png"
(root / "support" / "covers-user").mkdir(parents=True, exist_ok=True)
(root / "support" / "covers-user" / name).write_bytes(png)
now = datetime.datetime(2026, 11, 21, 12, 0, 0, tzinfo=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rec = {"key": key, "status": "confirmed", "productName": "Example Glow", "producer": "Example Producer",
       "summary": "Invented example text for a screenshot: a soft glow effect.", "officialURL": "https://example.com/glow",
       "sourceURL": "https://example.com/glow", "retrievedAt": now, "userChoseURL": True, "userChoseImage": True, "updatedAt": now,
       "cover": {"fileName": name, "origin": "userLocal", "rights": "userSupplied", "pixelWidth": w, "pixelHeight": h, "obtainedAt": now}}
(root / "support" / "enrichment.json").write_text(json.dumps({"schemaVersion": 1, "records": {key: rec}, "notFound": {}}, indent=1))
print(name)
