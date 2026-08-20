# eLSOP — GCIT SOP Knowledge Portal

A modern SOP Knowledge Portal for ACOSTA/GCIT, built as a Python-generated static site and hosted on GitHub Pages.

## What it contains

- **Homepage** — search, department cards, recently updated SOPs, bookmarks, dark mode
- **SOP Library** — grid/list view, filter by department/category/status/owner, sort, full-text search
- **SOP Reader** — book-style reading experience with TOC, section collapse, progress bar, comments, download, print
- **Dashboard** — KPI cards, department/status charts, most viewed, recently updated
- **Formal SOPs page** — 21 ACOSTA-only .docx downloads grouped alphabetically
- **12 sample SOPs** with full structured content (expandable to hundreds)

## Architecture

```
eLSOP/
  build.py             ← Python site generator (reads data/, renders templates/, writes site/)
  data/
    sops.json          ← All SOP records (add new SOPs here)
  templates/
    base.html.j2       ← Shared layout: nav, global search, dark mode, footer
    index.html.j2      ← Homepage
    library.html.j2    ← SOP library with filters
    reader.html.j2     ← Book reader per SOP
    dashboard.html.j2  ← Dashboard
  static/
    portal.css         ← Full design system (light + dark mode, responsive)
  site/                ← OUTPUT — what GitHub Pages serves (do not edit manually)
    index.html
    library.html
    dashboard.html
    reader/
      SOP-GCIT-001.html
      SOP-GCIT-002.html
      ...
    portal.css
    sops.html          ← Legacy formal SOPs page (ACOSTA only)
    sops/              ← Formal SOP .docx files
  .github/workflows/
    deploy.yml         ← GitHub Actions: runs build.py then deploys site/
```

## How it works

On every push to `main`, GitHub Actions:
1. Sets up Python 3.12
2. Installs `jinja2`
3. Runs `python build.py` — generates all HTML pages into `site/`
4. Deploys `site/` to GitHub Pages

## GitHub Pages setup

1. Push this repository to GitHub
2. Go to **Settings → Pages**
3. Under **Source**, select **GitHub Actions**
4. Push to `main` — the site deploys automatically

## Adding a new SOP

Edit [`data/sops.json`](data/sops.json) — add a new object with these fields:

```json
{
  "id": "SOP-GCIT-013",
  "title": "Your SOP Title",
  "department": "Claims",
  "category": "Customer SOP",
  "owner": "GCIT Team",
  "version": "1.0",
  "status": "Active",
  "updated": "2025-01-01",
  "created": "2025-01-01",
  "views": 0,
  "description": "Short description shown on library cards.",
  "file": "sops/Your_File.docx",
  "tags": ["tag1", "tag2"],
  "sections": [
    { "id": "purpose",     "title": "Purpose",                 "content": "..." },
    { "id": "scope",       "title": "Scope",                   "content": "..." },
    { "id": "definitions", "title": "Definitions",             "content": "..." },
    { "id": "roles",       "title": "Roles & Responsibilities", "content": "..." },
    { "id": "procedure",   "title": "Procedure Steps",         "content": "..." },
    { "id": "references",  "title": "References",              "content": "..." },
    { "id": "revisions",   "title": "Revision History",        "content": "..." },
    { "id": "related",     "title": "Related Documents",       "content": "..." }
  ]
}
```

Then commit and push — the site rebuilds and deploys automatically.

## Running the build locally

```bash
pip install jinja2
python build.py
```

Then open `site/index.html` in your browser.

## Regenerating customer matrix data

If `Customer_Matrix.xlsx` is updated:

```powershell
powershell -ExecutionPolicy Bypass -File "site/rebuild-customers.ps1"
```

Then commit and push the updated `site/customers.js`.
