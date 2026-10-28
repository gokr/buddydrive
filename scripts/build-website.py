#!/usr/bin/env python3
"""Render website/content/*.md into the static site in website/dist/.

The site is served by GitHub Pages from website/dist/, so this script is the
only thing that turns the markdown sources into what visitors see.

Pages come in two shapes:

  * the four inner pages (docs, features, security, how-it-works) are a plain
    markdown body wrapped in the shared nav, page header and footer;
  * index.html is a designed landing page whose content is prose in
    index.md but whose layout is bespoke, so it is built from named blocks
    (hero, features, steps, comparison, cta) rather than from the whole file.

Anything the markdown does not express (the page header blurb, the meta
description, the landing-page blurbs) lives in website/pages.toml. Assets
(styles.css, script.js, images/) are not generated; the script leaves them
alone.

Usage:
  scripts/build-website.py            # write website/dist/
  scripts/build-website.py --check    # exit 1 if dist/ is out of date
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import markdown
except ImportError:  # pragma: no cover - exercised by the error path only
    sys.exit(
        "build-website: the 'markdown' module is missing.\n"
        "  Debian/Ubuntu: sudo apt install python3-markdown\n"
        "  pip:           pip install markdown"
    )

ROOT = Path(__file__).resolve().parent.parent
WEBSITE = ROOT / "website"
CONTENT = WEBSITE / "content"
DIST = WEBSITE / "dist"
PAGES_TOML = WEBSITE / "pages.toml"

# The order of this list is the order pages are reported in.
MARKDOWN_PAGES = ["index", "features", "security", "how-it-works", "docs"]
INNER_PAGES = ["features", "security", "how-it-works", "docs"]

NAV = """    <nav class="navbar">
        <div class="container">
            <a href="index.html" class="logo">
                <img src="images/buddydrive-icon.png" alt="BuddyDrive" class="logo-img">
                <span class="logo-text">BuddyDrive</span>
            </a>
            <button class="nav-toggle" aria-label="Toggle navigation">
                <span></span><span></span><span></span>
            </button>
            <ul class="nav-menu">
                <li><a href="features.html">Features</a></li>
                <li><a href="security.html">Security</a></li>
                <li><a href="how-it-works.html">How It Works</a></li>
                <li><a href="docs.html">Docs</a></li>
                <li><a href="https://github.com/gokr/buddydrive" class="nav-cta">GitHub</a></li>
            </ul>
        </div>
    </nav>
"""

FOOTER = """    <footer class="footer">
        <div class="container">
            <div class="footer-grid">
                <div class="footer-brand">
                    <a href="index.html" class="logo">
                        <img src="images/buddydrive-icon.png" alt="BuddyDrive" class="logo-img">
                        <span class="logo-text">BuddyDrive</span>
                    </a>
                    <p>Backup your life, with a friend.</p>
                </div>
                <div class="footer-column">
                    <h4>Resources</h4>
                    <ul>
                        <li><a href="https://github.com/gokr/buddydrive">GitHub</a></li>
                        <li><a href="docs.html">Documentation</a></li>
                        <li><a href="features.html">Features</a></li>
                        <li><a href="security.html">Security</a></li>
                        <li><a href="how-it-works.html">How It Works</a></li>
                    </ul>
                </div>
                <div class="footer-column">
                    <h4>Community</h4>
                    <ul>
                        <li><a href="https://github.com/gokr/buddydrive/issues">Issues</a></li>
                        <li><a href="https://github.com/gokr/buddydrive/discussions">Discussions</a></li>
                    </ul>
                </div>
            </div>
            <div class="footer-bottom">
                <p>Released under the MIT License.</p>
                <p>100% Open Source. Your data, your rules.</p>
            </div>
        </div>
    </footer>
"""

HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
    <meta name="description" content="{description}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="styles.css">
    <link rel="icon" href="images/buddydrive-icon.png" type="image/png">
</head>
<body>
"""


# --------------------------------------------------------------------------
# markdown source handling
# --------------------------------------------------------------------------


@dataclass
class Source:
    """One page's markdown, split into frontmatter and body."""

    name: str
    meta: dict[str, str]
    body: str
    sections: dict[str, list[str]] = field(default_factory=dict)

    def section(self, heading: str) -> list[str]:
        return self.sections.get(heading, [])


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Read the '--- key: value ---' block at the top of a content file."""
    meta: dict[str, str] = {}
    if not text.startswith("---\n"):
        return meta, text
    end = text.find("\n---\n", 3)
    if end == -1:
        return meta, text
    for line in text[4:end].splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta, text[end + len("\n---\n") :]


def split_sections(body: str) -> dict[str, list[str]]:
    """Group the body into '## heading' -> lines, keeping code fences intact.

    Used only by the landing page, which addresses sections by name.
    """
    sections: dict[str, list[str]] = {}
    current: str | None = None
    fenced = False
    for line in body.splitlines():
        if line.startswith("```"):
            fenced = not fenced
        if not fenced and line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
            continue
        if current is not None:
            sections[current].append(line)
    return sections


def load(name: str) -> Source:
    path = CONTENT / f"{name}.md"
    if not path.exists():
        sys.exit(f"build-website: missing {path.relative_to(ROOT)}")
    meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    return Source(name=name, meta=meta, body=body, sections=split_sections(body))


# --------------------------------------------------------------------------
# the small TOML reader for pages.toml
# --------------------------------------------------------------------------


def load_pages_toml(path: Path) -> dict[str, dict]:
    """Read the tiny subset of TOML used by pages.toml.

    Deliberately minimal (sections, quoted/bare values, multi-line arrays of
    strings) so the generator needs nothing beyond the standard library; if
    pages.toml ever grows past this, switch to tomllib.
    """
    if not path.exists():
        sys.exit(f"build-website: missing {path.relative_to(ROOT)}")
    pages: dict[str, dict] = {}
    section: dict | None = None
    pending_key: str | None = None
    pending: list[str] = []

    def store(target: dict, key: str, raw: str) -> None:
        raw = raw.strip().rstrip(",")
        if raw.startswith("[") or pending_key is not None:
            target[key] = pending
        elif raw in ("true", "false"):
            target[key] = raw == "true"
        else:
            target[key] = unquote(raw)

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if pending_key is not None:
            if stripped.startswith("]"):
                pending_key = None
                continue
            if stripped:
                pending.append(unquote(stripped.rstrip(",")))
            continue
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            page_id = stripped[1:-1].strip()
            section = pages.setdefault(page_id, {})
            continue
        if section is None:
            continue
        key, sep, value = stripped.partition("=")
        if not sep:
            continue
        key, value = key.strip(), value.strip()
        if value.startswith("[") and not value.endswith("]"):
            pending_key, pending = key, []
            continue
        store(section, key, value)
    return pages


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------


def md() -> markdown.Markdown:
    return markdown.Markdown(extensions=["tables", "fenced_code", "attr_list"])


def inline(text: str) -> str:
    """Render one line of markdown without turning it into a paragraph."""
    return md().convert(text.strip()).removeprefix("<p>").removesuffix("</p>")


def field_line(line: str) -> tuple[str, str] | None:
    """Parse a '**Label:** value' directive line."""
    match = re.match(r"^\*\*(.+?):\*\*\s*(.*)$", line.strip())
    if not match:
        return None
    return match.group(1).strip(), match.group(2).strip()


def render_body(source: Source) -> str:
    return md().convert(source.body)


def page_header(title: str, blurb: str) -> str:
    return (
        "\n    <header class=\"page-header\">\n"
        "        <div class=\"container\">\n"
        f"            <h1>{html.escape(title)}</h1>\n"
        f"            <p>{html.escape(blurb)}</p>\n"
        "        </div>\n"
        "    </header>\n"
    )


def render_inner_page(source: Source, meta: dict) -> str:
    title = source.meta.get("title") or meta.get("title") or source.name.title()
    page_title = meta.get("title") or f"{title} - BuddyDrive"
    description = meta.get("description", "")
    blurb = meta.get("blurb", "")
    return (
        HEAD.format(title=html.escape(page_title), description=html.escape(description, quote=True))
        + NAV
        + page_header(title, blurb)
        + "\n    <main class=\"content-page\">\n"
        + indent(render_body(source), 8)
        + "\n    </main>\n\n"
        + FOOTER
        + "\n    <script src=\"script.js\"></script>\n</body>\n</html>\n"
    )


def indent(text: str, spaces: int) -> str:
    """Indent a block of HTML for readability, but never inside <pre>.

    Whitespace inside <pre> is content, so indenting those lines would show up
    as leading spaces in every code sample on the page.
    """
    pad = " " * spaces
    out: list[str] = []
    in_pre = False
    for line in text.strip().splitlines():
        if "<pre>" in line:
            in_pre = True
        elif "</pre>" in line:
            out.append(pad + line)
            in_pre = False
            continue
        if in_pre:
            out.append(line)
        else:
            out.append(pad + line if line.strip() else line)
    return "\n".join(out)


def render_hero(source: Source, meta: dict) -> str:
    """The landing page hero: the '**Label:** value' lines at the top of index.md."""
    values: dict[str, str] = {}
    for line in source.section("Hero Section"):
        parsed = field_line(line)
        if parsed:
            values[parsed[0]] = parsed[1]
    title = values.get("Title", source.meta.get("title", "BuddyDrive"))
    subtitle = values.get("Subtitle", source.meta.get("tagline", ""))
    description = values.get("Description", "")
    primary = values.get("CTA Primary", "Get Started")
    secondary = values.get("CTA Secondary", "Learn More")
    meta_primary = meta.get("cta_primary_href", "docs.html")
    meta_secondary = meta.get("cta_secondary_href", "features.html")
    badge = meta.get("badge", "Encrypted Backup &amp; Restore")
    badge = badge.replace("&amp;", "&")
    return f"""    <section class="hero">
        <div class="hero-bg">
            <div class="gradient-orb orb-1"></div>
            <div class="gradient-orb orb-2"></div>
            <div class="grid-pattern"></div>
        </div>
        <div class="container">
            <div class="hero-content">
                <div class="hero-badge">
                    <span class="badge-dot"></span>
                    {html.escape(badge)}
                </div>
                <h1 class="hero-title"><span class="gradient-text">{html.escape(subtitle or title)}</span></h1>
                <p class="hero-subtitle">
                    {html.escape(description)}
                </p>
                <div class="hero-cta">
                    <a href="{meta_primary}" class="btn btn-primary">{html.escape(primary)}</a>
                    <a href="{meta_secondary}" class="btn btn-secondary">{html.escape(secondary)}</a>
                </div>
            </div>
            <div class="hero-image">
                <img src="images/buddydrive.png" alt="BuddyDrive" width="400" height="400">
            </div>
        </div>
    </section>
"""


def parse_cards(source: Source) -> list[dict]:
    """Every '### Title {icon=X}' subsection in the file becomes a card.

    Scanning the whole file (not one section) means the landing page's cards are
    simply that page's '###' headings, with the icon on the heading itself.
    """
    lines = source.body.splitlines()
    cards: list[dict] = []
    title: str | None = None
    body: list[str] = []
    icon = ""

    def flush() -> None:
        if title is None:
            return
        text = " ".join(
            re.sub(r"<[^>]+>", "", para).strip()
            for para in paragraphs(md().convert("\n".join(body).strip()))
        )
        label = icon or re.sub(r"[^A-Za-z0-9]", "", title)[:5]
        cards.append({"title": title, "text": text, "icon": label})

    fenced = False
    for line in lines:
        if line.startswith("```"):
            fenced = not fenced
        match = None if fenced else re.match(r"^###\s+(.+?)\s*\{icon=([^}]+)\}\s*$", line)
        if match:
            flush()
            title, icon, body = match.group(1).strip(), match.group(2).strip(), []
            continue
        if not fenced and line.startswith("### "):
            flush()
            title, icon, body = line[4:].strip(), "", []
            continue
        if not fenced and line.startswith("## "):
            # A new top-level section ends the card list; its prose is not a card.
            flush()
            title = None
            continue
        if title is not None:
            body.append(line)
    flush()
    return cards


def render_feature_cards(cards: list[dict]) -> str:
    rendered = []
    for card in cards:
        rendered.append(
            "                <div class=\"feature-card\">\n"
            f"                    <div class=\"feature-icon\">{html.escape(card['icon'])}</div>\n"
            f"                    <h3>{html.escape(card['title'])}</h3>\n"
            f"                    <p>{card['text']}</p>\n"
            "                </div>"
        )
    return "\n".join(rendered)


def parse_steps(source: Source) -> list[dict]:
    """The ordered list under '## How It Works': '**Title** rest of the line'."""
    resolved = md()
    resolved.convert("\n".join(source.section("How It Works")).strip())
    steps: list[dict] = []
    for item in re.findall(r"<li>(.*?)</li>", resolved.convert(
            "\n".join(source.section("How It Works")).strip()), flags=re.S):
        lead = re.match(r"<strong>(.*?)</strong>\s*(.*)", item, flags=re.S)
        if not lead:
            continue
        text = re.sub(r"<[^>]+>", "", lead.group(2)).strip()
        steps.append({"title": re.sub(r"<[^>]+>", "", lead.group(1)).strip(), "text": text})
    return steps


def render_steps(items: list[dict]) -> str:
    rendered = []
    for number, item in enumerate(items, start=1):
        rendered.append(
            "                <div class=\"step\">\n"
            f"                    <div class=\"step-number\">{number}</div>\n"
            f"                    <h3>{html.escape(item['title'])}</h3>\n"
            f"                    <p>{html.escape(item['text'])}</p>\n"
            "                </div>"
        )
    return "\n".join(rendered)


def parse_comparison(source: Source) -> tuple[str, str, list[tuple[str, str]]]:
    """The two-column table under '## The Problem With Cloud Backups'."""
    resolved = md()
    resolved.convert("\n".join(source.section("The Problem With Cloud Backups")).strip())
    body = resolved.convert("\n".join(source.section("The Problem With Cloud Backups")).strip())
    headers = [re.sub(r"<[^>]+>", "", h).strip()
               for h in re.findall(r"<th>(.*?)</th>", body, flags=re.S)]
    rows: list[tuple[str, str]] = []
    for row in re.findall(r"<tr>(.*?)</tr>", body, flags=re.S):
        cells = re.findall(r"<td>(.*?)</td>", row, flags=re.S)
        if len(cells) == 2:
            rows.append((cells[0].strip(), cells[1].strip()))
    left, right = (headers + ["", ""])[:2]
    return left, right, rows


def render_comparison(left: str, right: str, rows: list[tuple[str, str]]) -> str:
    body = []
    for cloud, buddy in rows:
        body.append(
            "                    <tr>\n"
            f"                        <td>{cloud}</td>\n"
            f"                        <td>{buddy}</td>\n"
            "                    </tr>"
        )
    return f"""    <section style="background: var(--color-bg-secondary); padding: 80px 0;">
        <div class="container">
            <h2 class="section-title">{html.escape(left)} vs {html.escape(right)}</h2>
            <table class="comparison-table">
                <thead>
                    <tr>
                        <th>{html.escape(left)}</th>
                        <th>{html.escape(right)}</th>
                    </tr>
                </thead>
                <tbody>
{chr(10).join(body)}
                </tbody>
            </table>
        </div>
    </section>
"""


def prose(source: Source, heading: str) -> str:
    """One section's markdown as HTML, for the plain sections of the landing page."""
    lines = source.section(heading)
    return md().convert("\n".join(lines).strip())


def paragraphs(text: str) -> list[str]:
    """The plain paragraphs of a rendered markdown chunk."""
    return re.findall(r"<p>(.*?)</p>", text, flags=re.S)


def bullets(text: str) -> list[str]:
    items = re.findall(r"<li>(.*?)</li>", text, flags=re.S)
    return [re.sub(r"</?p>", "", item).strip() for item in items]


def render_index(source: Source, meta: dict) -> str:
    page_title = meta.get("title") or "BuddyDrive - Backup your life, with a friend"
    description = meta.get("description", "")

    why_sub = source.meta.get("why_subtitle") or meta.get("why_subtitle", "")

    cards = render_feature_cards(parse_cards(source))
    steps = render_steps(parse_steps(source))

    how = prose(source, "How It Works")
    how_lead = paragraphs(how)
    how_intro = how_lead[0] if how_lead else ""

    comparison = render_comparison(*parse_comparison(source))

    who = bullets(prose(source, "Who Is This For?"))
    who_list = "".join(f"\n                <li>{item}</li>" for item in who)

    get_started = prose(source, "Get Started")
    get_started_html = indent(get_started, 16)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{html.escape(page_title)}</title>
    <meta name="description" content="{html.escape(description, quote=True)}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="styles.css">
    <link rel="icon" href="images/buddydrive-icon.png" type="image/png">
</head>
<body>
{NAV}
{render_hero(source, meta)}
    <section class="features">
        <div class="container">
            <h2 class="section-title">Why BuddyDrive?</h2>
            <p class="section-subtitle">{html.escape(why_sub)}</p>

            <div class="feature-grid">
{cards}
            </div>
        </div>
    </section>

    <section class="content-page" style="max-width: 1000px; padding: 80px 24px;">
        <div class="container">
            <h2 class="section-title">How It Works</h2>
            <p class="section-subtitle" style="text-align: center; margin-bottom: 48px;">
                {how_intro}
            </p>
            <div class="steps">
{steps}
            </div>
        </div>
    </section>

{comparison}
    <section class="cta-section">
        <div class="container">
            <h2>Who Is This For?</h2>
            <p>{html.escape(meta.get("who_blurb", ""))}</p>
            <ul class="audience-list">{who_list}
            </ul>
            <div class="hero-cta">
                <a href="{meta.get("cta_primary_href", "docs.html")}" class="btn btn-primary">{html.escape(meta.get("cta_primary", "Get Started"))}</a>
                <a href="{meta.get("cta_secondary_href", "security.html")}" class="btn btn-secondary">{html.escape(meta.get("cta_secondary", "Security Details"))}</a>
            </div>
        </div>
    </section>

    <section class="content-page" style="max-width: 1000px; padding: 60px 24px 20px;">
        <div class="container">
{get_started_html}
        </div>
    </section>

{FOOTER}
    <script src="script.js"></script>
</body>
</html>
"""


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def build() -> dict[Path, str]:
    pages_meta = load_pages_toml(PAGES_TOML)
    outputs: dict[Path, str] = {}

    for name in MARKDOWN_PAGES:
        source = load(name)
        meta = pages_meta.get(name, {})
        if name == "index":
            outputs[DIST / "index.html"] = render_index(source, meta)
        else:
            outputs[DIST / f"{name}.html"] = render_inner_page(source, meta)

    # A sitemap is cheap and keeps the Pages deployment honest.
    urls = "".join(
        f"    <url><loc>https://buddydrive.org/{p}</loc></url>\n"
        for p in ["", "features.html", "security.html", "how-it-works.html", "docs.html"]
    )
    outputs[DIST / "sitemap.xml"] = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{urls}</urlset>\n"
    )
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="do not write; exit 1 if any page would change",
    )
    args = parser.parse_args()

    outputs = build()
    stale = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current != content:
            stale.append(path)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")

    names = ", ".join(sorted(p.name for p in outputs))
    if args.check:
        if stale:
            print("build-website: out of date: " + ", ".join(sorted(p.name for p in stale)))
            print("run scripts/build-website.py and commit the result")
            return 1
        print(f"build-website: up to date ({names})")
        return 0

    if stale:
        print("build-website: wrote " + ", ".join(sorted(p.name for p in stale)))
    else:
        print(f"build-website: already up to date ({names})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
