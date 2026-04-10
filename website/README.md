# BuddyDrive Website

This directory contains the static website for BuddyDrive.

## Structure

This website uses a **content-driven static site** approach:

```
website/
├── content/           # Markdown content (edit these!)
│   ├── index.md      # Home page content
│   ├── features.md   # Features page
│   ├── security.md   # Security and encryption details
│   ├── how-it-works.md # Technical architecture
│   └── docs.md       # Getting started guide
└── dist/             # Generated HTML (do not edit directly)
    ├── index.html
    ├── features.html
    ├── security.html
    ├── how-it-works.html
    ├── docs.html
    ├── styles.css
    └── script.js
```

## How to Update Content

1. **Edit the markdown files** in `content/` - these are the source of truth
2. **Ask Claude to regenerate** the HTML site
3. **The `dist/` folder** contains the generated site ready for deployment

### Example Workflow

```bash
# Edit content files
vim content/features.md

# Ask Claude: "Regenerate the website from the content files"
# Claude updates the dist/ folder with new HTML

# Preview locally:
cd website/dist
python -m http.server 8000
# Open http://localhost:8000
```

## Content Format

Content files use YAML frontmatter for metadata:

```markdown
---
title: Page Title
tagline: Optional tagline
---

## Section Heading

Regular markdown content here.
```

## Pages

- **Home** (`index.html`) - Hero, features overview, value proposition
- **Features** (`features.html`) - Detailed feature list
- **Security** (`security.html`) - Encryption and security details
- **How It Works** (`how-it-works.html`) - Technical architecture
- **Documentation** (`docs.html`) - Getting started guide

## Deployment

The `dist/` folder contains a completely static website. Deploy it to any static hosting.

To deploy:

```bash
# The dist/ folder can be deployed directly
# Copy contents to your web server, GitHub Pages, Netlify, etc.
```

## Design

- Modern dark theme matching BuddyDrive brand
- Accent colors from logo (blue/teal tones)
- Inter font for text, JetBrains Mono for code
- Fully responsive
- Smooth animations and transitions

## Brand Colors

From BuddyDrive logo:
- Primary: Deep blue
- Accent: Teal/cyan
- Background: Dark navy
- Text: Light gray/white

## License

MIT (same as BuddyDrive)
