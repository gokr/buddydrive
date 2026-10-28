# BuddyDrive Website

The static site published at **buddydrive.org** (GitHub Pages). It is generated:
`website/dist/` is what gets served, and it is built from `website/content/`.

```
website/
├── content/           # markdown sources — edit these
│   ├── index.md       # landing page: hero, cards, steps, comparison, CTA
│   ├── features.md
│   ├── security.md
│   ├── how-it-works.md
│   └── docs.md
├── pages.toml         # what markdown cannot express: <title>, meta description,
│                      # page-header blurb, the landing page subtitle
└── dist/              # GENERATED — do not edit by hand
    ├── index.html
    ├── features.html
    ├── security.html
    ├── how-it-works.html
    ├── docs.html
    ├── sitemap.xml
    ├── styles.css     # hand-written, never overwritten
    ├── script.js      # hand-written, never overwritten
    └── images/        # hand-written, never overwritten
```

## Editing

```bash
# edit the markdown, then regenerate dist/
$EDITOR website/content/features.md
scripts/build-website.py          # or: make website

# verify dist/ is up to date without writing (what CI runs)
scripts/build-website.py --check
```

Commit the change to `content/` **and** the regenerated `dist/` together. The
Pages workflow runs `--check` before deploying, so a source change that was never
rendered fails the build instead of quietly not shipping.

`styles.css`, `script.js` and `images/` are **not** generated — the script only
writes the HTML pages and `sitemap.xml`, so restyling the site by hand is fine.

## How the pages are built

Four pages (`features`, `security`, `how-it-works`, `docs`) are plain markdown
wrapped in the shared nav, page header and footer. Their header blurb and meta
description come from `pages.toml`.

The landing page is laid out specially, so it is assembled from named blocks of
`index.md`:

| Page block | Comes from |
|---|---|
| Hero | the `**Label:** value` lines under `## Hero Section` |
| Feature cards | **every** `### Title {icon=X}` in the file, in order |
| Steps | the ordered list under `## How It Works` |
| Comparison table | the two-column table under `## The Problem With Cloud Backups` |
| Who is this for | the list under `## Who Is This For?` |
| Get started | the prose under `## Get Started` |

To add a feature card, add a `###` heading with an `{icon=…}` attribute; the icon
text is whatever short label you want in the card's corner.

## Preview locally

```bash
cd website/dist && python3 -m http.server 8000
# open http://localhost:8000
```

## Design

Dark theme, accent colours from the logo (deep blue / teal), Inter for text and
JetBrains Mono for code. Styles live in `dist/styles.css`.

## License

MIT (same as BuddyDrive).
