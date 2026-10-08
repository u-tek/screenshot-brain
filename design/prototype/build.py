"""Builds the clickable prototype from the design/v4 screens.

    python3 design/prototype/build.py <v4 dir> <out dir>

Copies each screen as-is, adds the Inter webfont (phones don't have Inter installed) and proto.js
(the taps and navigation), and writes the shell as index.html. The out dir is what gets published.
"""
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCREENS = ["scan", "home", "saved", "reveals", "item", "stillwant", "triage", "history",
           "recaptime", "story", "peak", "widget"]
SHARED = ["kit.js", "base.css", "system.css", "mono.woff2", "serif.woff2"]
FONT = ('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:opsz,wght@14..32,100..900&display=swap">')


def main(src: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name in SHARED:
        shutil.copy(src / name, out / name)
    shutil.copy(HERE / "proto.js", out / "proto.js")
    for name in SCREENS:
        html = (src / f"{name}.html").read_text()
        if "<head>" not in html or "</body>" not in html:
            raise SystemExit(f"{name}.html has no <head> or </body>")
        html = html.replace("<head>", "<head>" + FONT + '<meta name="viewport" content="width=393">', 1)
        html = html.replace("</body>", '<script src="proto.js"></script></body>', 1)
        (out / f"{name}.html").write_text(html)
    shutil.copy(HERE / "shell.html", out / "index.html")
    # A standalone copy of the shell for local testing (the publisher adds this skeleton itself).
    (out / "_local.html").write_text(
        '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>'
        + (HERE / "shell.html").read_text() + "</body></html>")
    print("built", len(SCREENS), "screens into", out)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
