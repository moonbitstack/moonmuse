#!/usr/bin/env python3
"""Render docs/api.html from the package interfaces and the doc comments.

`moon info` writes a `pkg.generated.mbti` per package; this reads those together with the
`///` comments above the declarations and writes one page. The page is generated, never
edited: the docs workflow re-runs this script and fails when the committed copy differs.

    moon info --target all
    python3 scripts/gen_api.py
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "docs" / "api.html"

MODULE = "moonbitstack/moonmuse"

# Reading order: the contract, the formats that answer it, the parts around one call, the
# server side, a local engine, and the wrappers that only watch.
GROUPS = [
    (
        "contract",
        "The contract",
        "The request, the reply, the two traits, and the event stream reader.",
        ["."],
    ),
    (
        "formats",
        "Wire formats",
        "One package per specification, each with a client and the reader and writer for its JSON.",
        ["openai", "anthropic", "gemini", "ollama", "bedrock"],
    ),
    (
        "around",
        "Around one call",
        "Tools, schemas, templates, the layers that wrap a provider, the catalogue, the counter and the scripted provider.",
        ["toolbox", "structured", "prompt", "layers", "models", "count", "fake"],
    ),
    (
        "serving",
        "Serving",
        "A provider turned into an API, and the one place a call becomes bytes.",
        ["serve", "transport"],
    ),
    ("local", "A local engine", "An inference engine and a chat template behind the same contract.", ["local"]),
    ("observation", "Observation", "Traces and metrics under the OpenTelemetry GenAI names.", ["otel"]),
]

# Added by `#derive`. They are public, but they are not what a reader came for.
DERIVED = {"equal", "not_equal", "to_repr", "op_equal", "to_string", "hash"}

KIND_LABEL = {
    "fn": "fn",
    "value": "let",
    "struct": "type",
    "enum": "type",
    "error": "error",
    "trait": "trait",
    "alias": "type",
}

TYPE_KINDS = {"struct", "enum", "error", "trait", "alias"}


# ── the interface file ───────────────────────────────────────────────────────


def parse_mbti(path: Path) -> list[dict]:
    lines = path.read_text(encoding="utf-8").splitlines()
    decls: list[dict] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.startswith("//") or line.startswith("package ") or line.startswith("import"):
            i += 1
            continue
        if line.startswith("}") or line.startswith("."):
            i += 1
            continue

        block: list[str] = []
        depth = 0
        while i < len(lines):
            current = lines[i]
            block.append(current)
            depth += current.count("{") - current.count("}")
            i += 1
            nxt = lines[i] if i < len(lines) else ""
            if depth <= 0 and (
                not nxt.strip()
                or nxt.startswith("//")
                or re.match(r"^pub(?:\s|\()", nxt)
                or nxt.startswith("priv ")
                or nxt.startswith("#")
            ):
                break

        text = "\n".join(block).strip()
        decl = classify(text)
        if decl:
            decls.append(decl)
    return decls


def classify(text: str) -> dict | None:
    first = text.splitlines()[0]

    m = re.match(r"pub(?:\([a-z]+\))?\s+(?:async\s+)?fn\s+([A-Za-z0-9_:]+)", first)
    if m:
        return {"kind": "fn", "name": m.group(1), "sig": text}

    m = re.match(r"pub\s+let\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "value", "name": m.group(1), "sig": text}

    m = re.match(r"pub(?:\([a-z]+\))?\s+suberror\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "error", "name": m.group(1), "sig": text}

    m = re.match(r"pub(?:\([a-z]+\))?\s+struct\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "struct", "name": m.group(1), "sig": text}

    m = re.match(r"pub(?:\([a-z]+\))?\s+enum\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "enum", "name": m.group(1), "sig": text}

    m = re.match(r"pub(?:\([a-z]+\))?\s+trait\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "trait", "name": m.group(1), "sig": text}

    m = re.match(r"pub(?:\([a-z]+\))?\s+typealias\s+([A-Za-z0-9_]+)", first)
    if m:
        return {"kind": "alias", "name": m.group(1), "sig": text}

    m = re.match(r"pub\s+type\s+([A-Za-z0-9_]+)\s*=", first)
    if m:
        return {"kind": "alias", "name": m.group(1), "sig": text}

    m = re.match(r"pub\s+impl\s+(.+)", first)
    if m:
        return {"kind": "impl", "name": "", "sig": m.group(1).strip()}

    return None


def attach_impls(decls: list[dict]) -> list[dict]:
    """Fold `pub impl Trait for Type` into the declaration of Type."""
    by_name = {d["name"]: d for d in decls if d["kind"] != "impl"}
    for decl in decls:
        if decl["kind"] != "impl":
            continue
        m = re.match(r"(.+?)\s+for\s+([A-Za-z0-9_]+)", decl["sig"])
        if not m:
            continue
        target = by_name.get(m.group(2))
        if target is None:
            continue
        trait = m.group(1).strip()
        target.setdefault("impls", [])
        if trait not in target["impls"]:
            target["impls"].append(trait)
    return [d for d in decls if d["kind"] != "impl"]


# ── the doc comments ─────────────────────────────────────────────────────────

PATTERNS = [
    (re.compile(r"pub(?:\([a-z]+\))?\s+(?:async\s+)?fn\s+([A-Za-z0-9_:]+)"), "name"),
    (re.compile(r"pub(?:\([a-z]+\))?\s*(?:suberror|struct|enum|trait|typealias)\s+([A-Za-z0-9_]+)"), "name"),
    (re.compile(r"pub\s+let\s+([A-Za-z0-9_]+)"), "name"),
    (re.compile(r"pub\s+impl\s+\S.*?\s+for\s+([A-Za-z0-9_]+)\s+with\s+fn\s+([A-Za-z0-9_]+)"), "method"),
    (re.compile(r"pub\s+impl\s+([A-Za-z0-9_]+)\s+with\s+([A-Za-z0-9_]+)::\{"), "extend"),
]


def decl_name(line: str) -> str | None:
    for pattern, how in PATTERNS:
        m = pattern.search(line)
        if not m:
            continue
        if how == "method":
            return m.group(1) + "::" + m.group(2)
        if how == "extend":
            return m.group(1) + "::" + m.group(2)
        return m.group(1)
    return None


def paragraphs_of(lines: list[str]) -> list[str]:
    out: list[str] = []
    current: list[str] = []
    for line in lines:
        if line:
            current.append(line)
        elif current:
            out.append(" ".join(current))
            current = []
    if current:
        out.append(" ".join(current))
    return out


def parse_docs(package: Path) -> dict[str, list[str]]:
    """Map a declaration name to the paragraphs above it.

    The comment block is `///|`, then `///` lines, then possibly attributes (`#derive`), then
    the declaration. Attributes are skipped: reading the comment as belonging to the
    attribute is how a page loses a type's description.
    """
    docs: dict[str, list[str]] = {}
    files = [f for f in sorted(package.glob("*.mbt")) if not f.name.endswith(("_test.mbt", "_wbtest.mbt"))]
    for file in files:
        lines = file.read_text(encoding="utf-8").splitlines()
        i = 0
        while i < len(lines):
            if not lines[i].startswith("///|"):
                i += 1
                continue
            i += 1
            block: list[str] = []
            while i < len(lines) and lines[i].startswith("///"):
                block.append(lines[i][3:].strip())
                i += 1
            while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("#")):
                i += 1
            if i >= len(lines):
                break
            # A method documented with `self` is the same item the interface calls `T::m`.
            name = decl_name(lines[i])
            if name is None:
                m = re.match(r"\s*(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z0-9_]+)\s*\(\s*self\s*:\s*([A-Za-z0-9_]+)", lines[i])
                if m:
                    name = m.group(2) + "::" + m.group(1)
            if name is None:
                continue
            found = paragraphs_of(block)
            if found and name not in docs:
                docs[name] = found
    return docs


def package_note(package: Path) -> tuple[str, list[str]]:
    """The comment at the head of `moon.pkg`: a first paragraph, then the rest."""
    head: list[str] = []
    for line in (package / "moon.pkg").read_text(encoding="utf-8").splitlines():
        if line.startswith("//"):
            head.append(line[2:].strip())
        elif not line.strip() and not head:
            continue
        else:
            break
    while head and head[-1] == "":
        head.pop()
    paragraphs = paragraphs_of(head)
    if not paragraphs:
        return "", []
    return paragraphs[0], paragraphs[1:]


# ── rendering ────────────────────────────────────────────────────────────────


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def slug(text: str) -> str:
    """An anchor that keeps case: `Cached` the type and `cached` the function are two items."""
    return re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-")


def pkg_id(path: str) -> str:
    return "pkg-root" if path == "." else "pkg-" + slug(path)


def render_sig(text: str) -> str:
    return '<div class="sig">' + esc(text) + "</div>"


def inline(text: str) -> str:
    """A paragraph with `backticks` turned into code spans, after escaping."""
    parts = esc(text).split("`")
    out = []
    for index, part in enumerate(parts):
        out.append("<code>" + part + "</code>" if index % 2 else part)
    return "".join(out)


def render_docs(paragraphs: list[str]) -> str:
    return "".join("<p>" + inline(p) + "</p>" for p in paragraphs)


def render_item(decl: dict, docs: dict[str, list[str]], anchor: str) -> str:
    name = decl["name"]
    parts = name.split("::")
    if len(parts) > 1:
        label = '<span class="dim">' + esc("::".join(parts[:-1])) + "::</span>" + esc(parts[-1])
    else:
        label = esc(name)

    body = [render_sig(decl["sig"])]
    body.append(render_docs(docs.get(name, [])))
    if decl.get("impls"):
        traits = ", ".join("<code>" + esc(t) + "</code>" for t in decl["impls"])
        body.append('<p class="impls">Implements ' + traits + "</p>")
    return (
        '<div class="item" id="' + anchor + '">\n'
        '<div class="name"><span class="kind">' + KIND_LABEL[decl["kind"]] + "</span>" + label + "</div>\n"
        '<div class="body">' + "".join(body) + "</div>\n</div>"
    )


def render_type(decl: dict, methods: list[dict], docs: dict[str, list[str]], anchor: str, path: str) -> str:
    """A type, then its methods: the interface lists a method as `T::m`, and a reader looks
    for it under `T`."""
    body = [render_sig(decl["sig"]), render_docs(docs.get(decl["name"], []))]
    if decl.get("impls"):
        traits = ", ".join("<code>" + esc(t) + "</code>" for t in decl["impls"])
        body.append('<p class="impls">Implements ' + traits + "</p>")
    if methods:
        rows = []
        for method in methods:
            rows.append(render_sig(method["sig"]))
            rows.append(render_docs(docs.get(method["name"], [])))
        body.append('<div class="methods">' + "".join(rows) + "</div>")
    return (
        '<div class="item" id="' + anchor + '">\n'
        '<div class="name"><span class="kind">' + KIND_LABEL[decl["kind"]] + "</span>" + esc(decl["name"]) + "</div>\n"
        '<div class="body">' + "".join(body) + "</div>\n</div>"
    )


def render_package(path: str) -> tuple[str, int]:
    package = SRC / path
    decls = attach_impls(parse_mbti(package / "pkg.generated.mbti"))
    docs = parse_docs(package)
    lede, rest = package_note(package)

    types = {d["name"]: d for d in decls if d["kind"] in TYPE_KINDS}
    methods: dict[str, list[dict]] = {}
    loose: list[dict] = []
    for decl in decls:
        if decl["kind"] in TYPE_KINDS:
            continue
        if decl["kind"] == "fn" and "::" in decl["name"]:
            owner = decl["name"].split("::")[0]
            if owner in types:
                methods.setdefault(owner, []).append(decl)
                continue
        if decl["kind"] == "fn" and decl["name"].split("::")[-1] in DERIVED and decl["name"] not in docs:
            continue
        loose.append(decl)

    order = {"trait": 0, "struct": 1, "enum": 2, "error": 3, "alias": 4, "value": 5, "fn": 6}
    items = []
    for name in sorted(types):
        decl = types[name]
        # A type that no one can construct is still worth listing, but its derived methods
        # are not: the interface prints them because `#derive` wrote them.
        kept = [m for m in methods.get(name, []) if m["name"].split("::")[-1] not in DERIVED or m["name"] in docs]
        kept.sort(key=lambda d: d["name"].split("::")[-1])
        items.append((order.get(decl["kind"], 9), name, render_type(decl, kept, docs, slug(path + "-" + name), path)))
    for decl in sorted(loose, key=lambda d: (order.get(d["kind"], 9), d["name"])):
        items.append((order.get(decl["kind"], 9), decl["name"], render_item(decl, docs, slug(path + "-" + decl["name"]))))
    items.sort(key=lambda row: (row[0], row[1]))

    note = ""
    if lede:
        note += '<p class="pkg-ref">' + inline(lede) + "</p>"
    for paragraph in rest:
        note += '<p class="pkg-note">' + inline(paragraph) + "</p>"

    title = "moonmuse" if path == "." else path.split("/")[-1]
    full = MODULE if path == "." else MODULE + "/" + path
    rendered = (
        '<section class="pkg" id="' + pkg_id(path) + '">\n'
        '<div class="pkg-head"><h3>' + esc(title) + "</h3>"
        '<span class="path">' + esc(full) + "</span></div>" + note + "\n" + "\n".join(row[2] for row in items) + "\n</section>"
    )
    counted = len(items) + sum(
        len([m for m in methods.get(n, []) if m["name"].split("::")[-1] not in DERIVED or m["name"] in docs])
        for n in types
    )
    return rendered, counted


TEMPLATE = """<!doctype html>
<html lang="en-US">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" id="theme-color" content="#F2EBDD">
<meta name="description" content="Every public type, function, value and trait in moonmuse, grouped by package and generated from the source.">
<title>API reference — moonmuse</title>
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Caveat:wght@600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/paper.css">
<script>
  (function () {
    var theme = "light";
    try {
      var saved = sessionStorage.getItem("moonmuse:theme");
      theme = saved || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    } catch (error) {
      theme = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    }
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
</head>
<body>

<a class="skip" href="#pkg-root">Skip to the reference</a>

<header class="bar">
  <div class="wrap bar-in">
    <a class="brand" href="index.html" aria-label="moonmuse, home">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="M4 5.5h16M4 12h16M4 18.5h9"/><circle cx="18.5" cy="18.5" r="2.4"/></svg>
      moonmuse
    </a>
    <nav class="nav" aria-label="Site">
      <a href="guide.html">Guide</a>
      <a href="formats.html">Formats</a>
      <a href="api.html" aria-current="page">API</a>
      <button id="theme" type="button" aria-pressed="false" aria-label="Switch the desk">
        <svg class="theme-icon moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M20 14.5A8.5 8.5 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/></svg>
        <svg class="theme-icon sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></svg>
        <span class="theme-word">Desk</span>
      </button>
      <a class="icon-link" href="https://github.com/moonbitstack/moonmuse" aria-label="The repository on GitHub">
        <svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
      </a>
    </nav>
  </div>
</header>

<main>
  <div class="wrap">
    <div class="head-page">
      <p class="eyebrow">Reference</p>
      <h1>Every package, in order</h1>
      <p class="lede">Generated from each package's interface file and the comments above its declarations: __COUNT__ public declarations across __PACKAGES__ packages. A type is followed by its methods, because that is where a reader looks for them.</p>
    </div>

    <div class="doc-shell api">
      <aside class="rail" aria-label="Contents">
        <div class="rail-title">Packages</div>
        <ol>
__RAIL__
        </ol>
      </aside>

      <div class="prose">
__BODY__
      </div>
    </div>
  </div>
</main>

<footer class="foot wrap">
  <span>moonmuse · Apache-2.0</span>
  <span class="links">
    <a href="guide.html">Guide</a>
    <a href="formats.html">Formats</a>
    <a href="api.html">API</a>
    <a href="https://mooncakes.io/docs/moonbitstack/moonmuse">mooncakes</a>
    <a href="https://github.com/moonbitstack/moonmuse">Repository</a>
  </span>
  <span class="spacer">No trackers, no cookies, no analytics</span>
</footer>

<button class="totop" id="totop" type="button" aria-label="Back to top">
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg>
</button>

<script src="assets/paper.js"></script>
</body>
</html>
"""


def check_complete(page: str) -> list[str]:
    """Every public declaration in every interface has to be on the page.

    A renderer that drops a kind of declaration (a type alias, a value, a method whose owner
    moved) reads as a complete page and is not one; this is the check that says so.
    """
    missing: list[str] = []
    for pkg in sorted(SRC.rglob("moon.pkg")):
        rel = pkg.parent.relative_to(SRC).as_posix()
        if rel.startswith("examples") or rel.startswith("snippet_check"):
            continue
        interface = pkg.parent / "pkg.generated.mbti"
        if not interface.exists():
            continue
        for decl in parse_mbti(interface):
            if decl["kind"] == "impl":
                continue
            name = decl["name"]
            if decl["kind"] == "fn" and name.split("::")[-1] in DERIVED:
                continue
            if esc(name) not in page:
                missing.append(rel + ": " + name)
    return missing


def fill_counts(packages: int) -> None:
    """Write the package count into the home page.

    It comes from the same walk of `src/` the reference is built from, so a package cannot be
    added without the home page agreeing.
    """
    index = ROOT / "docs" / "index.html"
    text = index.read_text(encoding="utf-8")
    text = re.sub(
        r'(<span data-count="packages">)\d+(</span>)',
        lambda m: m.group(1) + str(packages) + m.group(2),
        text,
    )
    index.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    rail: list[str] = []
    body: list[str] = []
    packages = 0
    count = 0

    for key, title, blurb, paths in GROUPS:
        present = [p for p in paths if (SRC / p / "moon.pkg").exists() or (p == "." and (SRC / "moon.pkg").exists())]
        if not present:
            continue
        rail.append('          <li><a href="#group-' + key + '"><span class="n">›</span>' + esc(title) + "</a></li>")
        for path in present:
            label = "moonmuse" if path == "." else path
            rail.append('          <li><a href="#' + pkg_id(path) + '" style="padding-left:22px">' + esc(label) + "</a></li>")
        body.append(
            '<div class="group" id="group-' + key + '"><div class="group-head"><h2>' + esc(title) + "</h2></div>"
            '<p class="pkg-note">' + esc(blurb) + "</p>"
        )
        for path in present:
            rendered, items = render_package(path)
            body.append(rendered)
            packages += 1
            count += items
        body.append("</div>")

    page = TEMPLATE.replace("__RAIL__", "\n".join(rail))
    page = page.replace("__BODY__", "\n".join(body))
    page = page.replace("__COUNT__", str(count))
    page = page.replace("__PACKAGES__", str(packages))

    missing = check_complete(page)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    fill_counts(packages)
    print("api.html: %d packages, %d declarations" % (packages, count))
    if missing:
        for item in missing:
            print("not on the page: " + item)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
