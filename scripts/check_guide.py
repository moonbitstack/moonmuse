"""Compile the listings on the guide page, and run the ones that print something.

A page that shows output is making a claim, so each listing under a `printed` block is built
as an executable, run on the native target, and its stdout compared with what the page says.
A listing without an output block only has to compile.

The page is read as HTML: `data-lang="mbt"` marks a listing, `data-target="native"` limits it
to one backend. Blocks of one page are checked one at a time — a reader copies one listing,
not the whole page — so a listing has to stand alone.

Usage: python scripts/check_guide.py [page ...]
"""

from __future__ import annotations

import html as htmllib
import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

spec = importlib.util.spec_from_file_location("check_snippets", ROOT / "scripts" / "check_snippets.py")
check_snippets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_snippets)

LISTING = re.compile(r'<pre data-lang="mbt"(?P<attrs>[^>]*)>(?P<code>.*?)</pre>', re.S)
PRINTED = re.compile(r'<div class="said[^"]*">.*?<b>printed</b>(?P<text>.*?)</div>', re.S)


def listing_code(raw: str) -> str:
    return htmllib.unescape(raw).strip("\n")


def printed_after(after: str) -> str | None:
    match = PRINTED.search(after)
    if not match:
        return None
    text = htmllib.unescape(match.group("text"))
    return text.strip("\n")


def program_of(code: str) -> tuple[str, bool]:
    """A whole program for one listing. A listing that already declares its own entry point
    is used as written; one made of statements is wrapped, which is what a reader does."""
    if re.search(r"^(async )?fn main", code, re.M):
        return code, True
    body = "\n".join("  " + line if line else "" for line in code.splitlines())
    return "async fn main raise {\n" + body + "\n}", True


def main() -> int:
    pages = [Path(p) for p in sys.argv[1:]] or [ROOT / "docs" / "guide.html"]
    module, src, deps = check_snippets.module_info()
    subprocess.run(["moon", "update"], cwd=ROOT, capture_output=True)
    aliases = check_snippets.packages(module, src, deps)

    failed = 0
    checked = 0
    for page in pages:
        page = page if page.is_absolute() else ROOT / page
        text = page.read_text(encoding="utf-8")
        for index, match in enumerate(LISTING.finditer(text), start=1):
            code = listing_code(match.group("code"))
            if not code:
                continue
            expected = printed_after(text[match.end() : match.end() + 900])
            native = "false" if 'data-target="all"' in match.group("attrs") else True
            program, _ = program_of(code)

            used = set(re.findall(r"@([a-z_][a-z0-9_]*)\.", program))
            imports = sorted(
                {aliases[a] for a in used if a in aliases}
                | {f"moonbitlang/core/{a}" for a in used if a not in aliases and a in check_snippets.CORE}
                | {f"moonbitlang/core/encoding/{a}" for a in used if a not in aliases and a in check_snippets.NESTED}
            )
            if "async fn main" in program and "moonbitlang/async" not in imports:
                imports.append("moonbitlang/async")

            pkg = SRC / "snippet_check"
            shutil.rmtree(pkg, ignore_errors=True)
            pkg.mkdir(parents=True)
            head = "import {\n" + "".join(f'  "{p}",\n' for p in imports) + "}\n" if imports else ""
            head += '\noptions("is-main": true)\n'
            (pkg / "moon.pkg").write_text(head, encoding="utf-8", newline="\n")
            (pkg / "main.mbt").write_text(program + "\n", encoding="utf-8", newline="\n")
            target = "native" if native else "all"
            try:
                run = subprocess.run(
                    ["moon", "run", "src/snippet_check", "--target", target],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )
            finally:
                shutil.rmtree(pkg, ignore_errors=True)

            checked += 1
            if run.returncode != 0:
                failed += 1
                print(f"{page.name}: listing {index} does not run")
                print((run.stdout + run.stderr).strip()[-1200:])
                continue
            if expected is None:
                print(f"{page.name}: listing {index} compiles and runs")
                continue
            got = run.stdout.replace("\r\n", "\n").strip("\n")
            want = expected.replace("\r\n", "\n").strip("\n")
            if got != want:
                failed += 1
                print(f"{page.name}: listing {index} printed something else")
                print("  want: " + repr(want))
                print("  got:  " + repr(got))
            else:
                print(f"{page.name}: listing {index} prints what the page says")

    print(f"{checked} listings checked, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
