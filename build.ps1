# build.ps1 - eLSOP Knowledge Portal PowerShell static site builder
# Run from eLSOP repo root: powershell.exe -ExecutionPolicy Bypass -File build.ps1

param([string]$Root = "")

if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = (Get-Location).Path }

$SiteDir   = Join-Path $Root "site"
$DataDir   = Join-Path $Root "data"
$StaticDir = Join-Path $Root "static"
$ReaderDir = Join-Path $SiteDir "reader"

$ErrorActionPreference = "Stop"
Write-Host "eLSOP PowerShell build starting..." -ForegroundColor Cyan
Write-Host "Root: $Root"

# Ensure reader dir
if (-not (Test-Path $ReaderDir)) {
    New-Item -ItemType Directory -Path $ReaderDir | Out-Null
    Write-Host "  Created: site/reader/"
}

# Copy static assets
if (Test-Path $StaticDir) {
    Get-ChildItem $StaticDir | ForEach-Object {
        $dest = Join-Path $SiteDir $_.Name
        Copy-Item $_.FullName $dest -Force
        Write-Host "  copied static: $($_.Name)"
    }
}

# Load sops.json
$sopsPath = Join-Path $DataDir "sops.json"
$sops = Get-Content $sopsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "  Loaded $($sops.Count) SOPs from sops.json"

$buildTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm") + " UTC"

# Compact sops JSON for embedding
$lightSops = $sops | ForEach-Object {
    $s = $_
    [ordered]@{
        id          = $s.id
        title       = $s.title
        department  = $s.department
        category    = $s.category
        owner       = $s.owner
        version     = $s.version
        status      = $s.status
        updated     = $s.updated
        views       = $s.views
        description = $s.description
        tags        = $s.tags
        file        = if ($s.file) { $s.file } else { "" }
    }
}
$sopsJson = ($lightSops | ConvertTo-Json -Depth 3 -Compress)

# Helpers
function EH($s) {
    if (-not $s) { return "" }
    return $s.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}
function StatusClass($st) { return "status-" + $st.ToLower().Replace(" ","-") }
function TruncateStr($s, $n) {
    if (-not $s) { return "" }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0,$n) + [char]0x2026
}

# Base nav + footer shared block
$THEME_ICON_SUN = '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>'

function Write-SopPage {
    param($sop, $prevSop, $nextSop, $depth)

    $sc = StatusClass $sop.status

    # nav buttons
    $prevBtn = if ($prevSop) { "<a class=`"page-nav-btn`" href=`"$($prevSop.id).html`">← $($prevSop.id)</a>" } else { "" }
    $nextBtn = if ($nextSop) { "<a class=`"page-nav-btn`" href=`"$($nextSop.id).html`">$($nextSop.id) →</a>" } else { "" }
    $prevBotBtn = if ($prevSop) { $pt = EH $prevSop.title; "<a class=`"page-nav-btn`" href=`"$($prevSop.id).html`">← Previous: $pt</a>" } else { "<span></span>" }
    $nextBotBtn = if ($nextSop) { $nt = EH $nextSop.title; "<a class=`"page-nav-btn`" href=`"$($nextSop.id).html`">Next: $nt →</a>" } else { "" }

    # Tags
    $tagsHtml = ($sop.tags | ForEach-Object { $t = EH $_; "<span class=`"tag`">$t</span>" }) -join " "

    # TOC links
    $tocLinks = @()
    for ($j = 0; $j -lt $sop.sections.Count; $j++) {
        $sec = $sop.sections[$j]
        $secTitle = EH $sec.title
        $tocLinks += "<a class=`"toc-link`" href=`"#$($sec.id)`" onclick=`"scrollToSection('$($sec.id)')`"><span class=`"toc-num`">$($j+1)</span> $secTitle</a>"
    }
    $tocLinksHtml = $tocLinks -join "`n      "

    # Download button
    $downloadBtn = ""
    if ($sop.file) {
        $downloadBtn = @"
      <a class="toc-action-btn" href="../$($sop.file)" download>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
        Download DOCX
      </a>
"@
    }

    # Version history banner
    $vhBanner = ""
    if ($sop.last_change) {
        $vhDesc   = EH $sop.last_change.description
        $vhDate   = EH $sop.last_change.date
        $vhAuthor = EH $sop.last_change.author
        $vhBanner = @"
    <div class="version-history-banner">
      <div class="vh-label">CURRENT VERSION HISTORY</div>
      <div class="vh-table">
        <div class="vh-col vh-col-desc"><div class="vh-head">UPDATE DESCRIPTION</div><div class="vh-val">$vhDesc</div></div>
        <div class="vh-col vh-col-date"><div class="vh-head">DATE</div><div class="vh-val">$vhDate</div></div>
        <div class="vh-col vh-col-author"><div class="vh-head">AUTHOR</div><div class="vh-val">$vhAuthor</div></div>
      </div>
    </div>
"@
    }

    # Sections
    $sectionsHtml = @()
    for ($j = 0; $j -lt $sop.sections.Count; $j++) {
        $sec  = $sop.sections[$j]
        $st   = EH $sec.title
        # encode content then convert newlines to <br>
        $sc2  = (EH $sec.content).Replace("&#xA;","<br>")
        $sc2  = $sc2 -replace "`r`n","<br>" -replace "`n","<br>" -replace "`r","<br>"
        $sectionsHtml += @"
    <section class="reader-section" id="$($sec.id)" data-section="$j">
      <div class="section-toggle" onclick="toggleSection('$($sec.id)')">
        <h2 class="section-title"><span class="section-num">$($j+1)</span> $st</h2>
        <svg class="section-chevron" id="chev-$($sec.id)" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      <div class="section-body" id="body-$($sec.id)">
        <div class="section-content">$sc2</div>
      </div>
    </section>
"@
    }
    $allSectionsHtml = $sectionsHtml -join ""

    $sopTitle   = EH $sop.title
    $sopDesc    = EH $sop.description

    $content = @"
<div class="reader-layout">
  <aside class="reader-toc" id="readerToc">
    <div class="toc-header">
      <div class="toc-sop-id">$($sop.id)</div>
      <div class="toc-sop-title">$sopTitle</div>
    </div>
    <div class="toc-meta">
      <div class="toc-meta-row"><span class="toc-meta-lbl">Version</span><span>v$($sop.version)</span></div>
      <div class="toc-meta-row"><span class="toc-meta-lbl">Dept</span><span>$(EH $sop.department)</span></div>
      <div class="toc-meta-row"><span class="toc-meta-lbl">Owner</span><span>$(EH $sop.owner)</span></div>
      <div class="toc-meta-row"><span class="toc-meta-lbl">Updated</span><span>$($sop.updated)</span></div>
      <div class="toc-meta-row"><span class="toc-meta-lbl">Status</span><span class="meta-status $sc">$($sop.status)</span></div>
    </div>
    <nav class="toc-nav">
      <div class="toc-nav-heading">Table of Contents</div>
      $tocLinksHtml
    </nav>
    <div class="toc-progress">
      <div class="toc-progress-lbl">Reading Progress</div>
      <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
      <div class="progress-pct" id="progressPct">0%</div>
    </div>
    <div class="toc-actions">
$downloadBtn
      <button class="toc-action-btn" onclick="window.print()">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>
        Print
      </button>
      <button class="toc-action-btn" id="bookmarkBtn" onclick="handleBookmark()">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>
        <span id="bookmarkLabel">Bookmark</span>
      </button>
    </div>
  </aside>
  <div class="reader-main" id="readerMain">
    <div class="reader-page-header">
      <a href="../library.html" class="reader-back">&#8592; Back to Library</a>
      <div class="reader-page-nav">$prevBtn$nextBtn</div>
    </div>
    <header class="reader-header">
      <div class="reader-header-top">
        <span class="sop-id-badge sop-id-lg">$($sop.id)</span>
        <span class="meta-status $sc">$($sop.status)</span>
        <span class="meta-ver">v$($sop.version)</span>
      </div>
      <h1 class="reader-title">$sopTitle</h1>
      <p class="reader-desc">$sopDesc</p>
      <div class="reader-tags">$tagsHtml</div>
    </header>
$vhBanner
$allSectionsHtml
    <section class="reader-section" id="comments">
      <div class="section-toggle" onclick="toggleSection('comments')">
        <h2 class="section-title"><span class="section-num">&#x1F4AC;</span> Comments &amp; Feedback</h2>
        <svg class="section-chevron" id="chev-comments" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      <div class="section-body" id="body-comments">
        <div class="comments-area">
          <div id="commentsList" class="comments-list"></div>
          <div class="comment-form">
            <input id="commentName" class="comment-input" placeholder="Your name" type="text">
            <textarea id="commentText" class="comment-textarea" placeholder="Leave a comment or feedback about this SOP…" rows="3"></textarea>
            <button class="comment-submit" onclick="submitComment()">Submit Feedback</button>
          </div>
        </div>
      </div>
    </section>
    <div class="reader-bottom-nav">
      $prevBotBtn
      $nextBotBtn
    </div>
  </div>
  <button class="toc-mobile-toggle" onclick="toggleMobileToc()" title="Table of Contents" aria-label="Toggle TOC">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
  </button>
</div>
"@

    $sid = $sop.id
    $scripts = @"
<script>
const SOP_ID = '$sid';
function toggleSection(id) {
  const body = document.getElementById('body-' + id);
  const chev = document.getElementById('chev-' + id);
  const open = body.style.display !== 'none';
  body.style.display = open ? 'none' : '';
  if (chev) chev.style.transform = open ? 'rotate(-90deg)' : '';
}
function scrollToSection(id) {
  const el = document.getElementById(id);
  if (!el) return;
  const body = document.getElementById('body-' + id);
  if (body) body.style.display = '';
  el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
const fill = document.getElementById('progressFill');
const pct  = document.getElementById('progressPct');
const secs = document.querySelectorAll('.reader-section[data-section]');
const tocL = document.querySelectorAll('.toc-link');
function updateProgress() {
  const scrollTop = window.scrollY;
  const docH = document.documentElement.scrollHeight - window.innerHeight;
  const p = docH > 0 ? Math.min(100, Math.round((scrollTop / docH) * 100)) : 0;
  fill.style.width = p + '%';
  pct.textContent = p + '%';
  let activeIdx = 0;
  secs.forEach((s, i) => { if (s.getBoundingClientRect().top < 120) activeIdx = i; });
  tocL.forEach((l, i) => l.classList.toggle('toc-link-active', i === activeIdx));
}
window.addEventListener('scroll', updateProgress, { passive: true });
function handleBookmark() {
  toggleBookmark(SOP_ID);
  const bm = isBookmarked(SOP_ID);
  document.getElementById('bookmarkLabel').textContent = bm ? 'Bookmarked \u2713' : 'Bookmark';
  document.getElementById('bookmarkBtn').classList.toggle('bookmarked', bm);
}
(function() {
  const bm = isBookmarked(SOP_ID);
  document.getElementById('bookmarkLabel').textContent = bm ? 'Bookmarked \u2713' : 'Bookmark';
  document.getElementById('bookmarkBtn').classList.toggle('bookmarked', bm);
})();
const COMMENT_KEY = 'comments_' + SOP_ID;
function loadComments() { try { return JSON.parse(localStorage.getItem(COMMENT_KEY) || '[]'); } catch { return []; } }
function renderComments() {
  const list = document.getElementById('commentsList');
  const comments = loadComments();
  if (!comments.length) { list.innerHTML = '<div class="no-comments">No comments yet.</div>'; return; }
  list.innerHTML = comments.map(c => '<div class="comment-item"><div class="comment-header"><strong>' + (c.name||'Anonymous') + '</strong><span class="comment-date">' + c.date + '</span></div><div class="comment-body">' + c.text + '</div></div>').join('');
}
function submitComment() {
  const name = document.getElementById('commentName').value.trim() || 'Anonymous';
  const text = document.getElementById('commentText').value.trim();
  if (!text) return;
  const comments = loadComments();
  comments.push({ name, text, date: new Date().toLocaleDateString() });
  localStorage.setItem(COMMENT_KEY, JSON.stringify(comments));
  document.getElementById('commentText').value = '';
  renderComments();
}
renderComments();
function toggleMobileToc() { document.getElementById('readerToc').classList.toggle('toc-mobile-open'); }
</script>
"@

    return Get-PageHtml -title "$sopTitle -- eLSOP" -depth $depth -navActive "" -content $content -scripts $scripts
}

function Get-PageHtml {
    param($title, $depth, $navActive, $content, $scripts)

    $nh = if ($navActive -eq "home")    { "active" } else { "" }
    $nl = if ($navActive -eq "library") { "active" } else { "" }
    $nd = if ($navActive -eq "dash")    { "active" } else { "" }
    $nm = if ($navActive -eq "matrix")  { "active" } else { "" }
    $ns = if ($navActive -eq "sops")    { "active" } else { "" }

    return @"
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title</title>
<link rel="stylesheet" href="${depth}portal.css">
<meta name="description" content="eLSOP Standard Operating Procedure Knowledge Portal">
</head>
<body>
<nav class="topnav">
  <div class="topnav-inner">
    <a class="brand" href="${depth}index.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
      </svg>
      <span class="brand-name">eLSOP</span><span class="brand-badge">SOP</span>
    </a>
    <div class="nav-links">
      <a href="${depth}index.html" class="nav-link $nh">Home</a>
      <a href="${depth}library.html" class="nav-link $nl">SOP Library</a>
      <a href="${depth}dashboard.html" class="nav-link $nd">Dashboard</a>
      <a href="${depth}customers.html" class="nav-link $nm">Customer Matrix</a>
      <a href="${depth}sops.html" class="nav-link $ns">Formal SOPs</a>
    </div>
    <div class="nav-actions">
      <div class="nav-search-wrap">
        <svg class="nav-search-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <input id="globalSearch" class="nav-search" type="text" placeholder="Search SOPs..." autocomplete="off">
        <div id="globalResults" class="global-results" style="display:none"></div>
      </div>
      <button class="theme-toggle" onclick="toggleTheme()" title="Toggle dark mode" aria-label="Toggle dark mode">
        <svg id="themeIcon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          $THEME_ICON_SUN
        </svg>
      </button>
    </div>
  </div>
</nav>
<main>
$content
</main>
<footer class="site-footer">
  <div class="footer-inner">
    <div class="footer-brand">eLSOP Knowledge Portal</div>
    <div class="footer-meta">Built $buildTime &nbsp;&middot;&nbsp; ACOSTA customers only</div>
    <div class="footer-made">Made with IBM Bob</div>
  </div>
</footer>
<script>
const ALL_SOPS = $sopsJson;
function toggleTheme() {
  const html = document.documentElement;
  const isDark = html.getAttribute('data-theme') === 'dark';
  html.setAttribute('data-theme', isDark ? 'light' : 'dark');
  localStorage.setItem('theme', isDark ? 'light' : 'dark');
  updateThemeIcon(!isDark);
}
function updateThemeIcon(dark) {
  const icon = document.getElementById('themeIcon');
  if (!icon) return;
  icon.innerHTML = dark ? '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>' : '$THEME_ICON_SUN';
}
(function() {
  const saved = localStorage.getItem('theme') || 'light';
  document.documentElement.setAttribute('data-theme', saved);
  updateThemeIcon(saved === 'dark');
})();
function getBookmarks() { try { return JSON.parse(localStorage.getItem('bookmarks') || '[]'); } catch { return []; } }
function toggleBookmark(id) {
  let bm = getBookmarks();
  if (bm.includes(id)) bm = bm.filter(x => x !== id); else bm.push(id);
  localStorage.setItem('bookmarks', JSON.stringify(bm));
  document.querySelectorAll('[data-bookmark="' + id + '"]').forEach(el => {
    el.classList.toggle('bookmarked', bm.includes(id));
    el.title = bm.includes(id) ? 'Remove bookmark' : 'Bookmark this SOP';
  });
}
function isBookmarked(id) { return getBookmarks().includes(id); }
const gs = document.getElementById('globalSearch');
const gr = document.getElementById('globalResults');
if (gs) {
  gs.addEventListener('input', function() {
    const q = this.value.trim().toLowerCase();
    if (!q) { gr.style.display = 'none'; return; }
    const hits = ALL_SOPS.filter(s =>
      s.title.toLowerCase().includes(q) || s.id.toLowerCase().includes(q) ||
      s.department.toLowerCase().includes(q) || (s.tags||[]).join(' ').toLowerCase().includes(q)
    ).slice(0, 8);
    if (!hits.length) { gr.style.display = 'none'; return; }
    const base = '${depth}';
    gr.innerHTML = hits.map(s => '<a class="gr-item" href="' + base + 'reader/' + s.id + '.html"><span class="gr-id">' + s.id + '</span><span class="gr-title">' + s.title + '</span><span class="gr-dept">' + s.department + '</span></a>').join('');
    gr.style.display = 'block';
  });
  document.addEventListener('click', e => { if (!gs.contains(e.target) && !gr.contains(e.target)) gr.style.display = 'none'; });
}
</script>
$scripts
</body>
</html>
"@
}

# ── Generate reader pages ─────────────────────────────────────────────────────
Write-Host "`nGenerating reader pages..."
for ($i = 0; $i -lt $sops.Count; $i++) {
    $sop  = $sops[$i]
    $prev = if ($i -gt 0)              { $sops[$i-1] } else { $null }
    $next = if ($i -lt $sops.Count-1)  { $sops[$i+1] } else { $null }

    $html = Write-SopPage -sop $sop -prevSop $prev -nextSop $next -depth "../"
    $outPath = Join-Path $ReaderDir "$($sop.id).html"
    [System.IO.File]::WriteAllText($outPath, $html, [System.Text.Encoding]::UTF8)
    Write-Host "  wrote: site/reader/$($sop.id).html"
}

# ── Generate library.html ─────────────────────────────────────────────────────
Write-Host "`nGenerating library.html..."

# Build filter sidebar options
$departments = $sops | ForEach-Object { $_.department } | Sort-Object -Unique
$categories  = $sops | ForEach-Object { $_.category  } | Sort-Object -Unique
$statuses    = $sops | ForEach-Object { $_.status    } | Sort-Object -Unique
$owners      = $sops | ForEach-Object { $_.owner     } | Sort-Object -Unique

function Radio-Options($name, $items) {
    $opts = "<label class=`"filter-opt`"><input type=`"radio`" name=`"$name`" value=`"`"> All</label>`n"
    foreach ($item in $items) {
        $v = EH $item
        $opts += "      <label class=`"filter-opt`"><input type=`"radio`" name=`"$name`" value=`"$v`"> $v</label>`n"
    }
    return $opts
}

$libContent = @"
<div class="lib-layout">
  <aside class="lib-sidebar">
    <div class="sidebar-section">
      <div class="sidebar-heading">Department</div>
      $(Radio-Options "dept" $departments)
    </div>
    <div class="sidebar-section">
      <div class="sidebar-heading">Category</div>
      $(Radio-Options "cat" $categories)
    </div>
    <div class="sidebar-section">
      <div class="sidebar-heading">Status</div>
      $(Radio-Options "status" $statuses)
    </div>
    <div class="sidebar-section">
      <div class="sidebar-heading">Owner</div>
      $(Radio-Options "owner" $owners)
    </div>
    <button class="clear-filters-btn" onclick="clearFilters()">Clear Filters</button>
  </aside>
  <div class="lib-main">
    <div class="lib-toolbar">
      <div class="lib-search-wrap">
        <svg class="lib-search-icon" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <input id="libSearch" class="lib-search" type="text" placeholder="Search SOPs..." oninput="applyFilters()">
      </div>
      <div class="lib-toolbar-right">
        <span id="libCount" class="count-badge"></span>
        <select id="sortSelect" onchange="applyFilters()" class="sort-select">
          <option value="updated">Recently Updated</option>
          <option value="title">Title A-Z</option>
          <option value="views">Most Viewed</option>
          <option value="id">SOP Number</option>
        </select>
        <div class="view-toggle">
          <button id="btnGrid" class="view-btn active" onclick="setView('grid')" title="Grid view">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
          </button>
          <button id="btnList" class="view-btn" onclick="setView('list')" title="List view">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
          </button>
        </div>
      </div>
    </div>
    <div id="libGrid" class="card-grid lib-grid"></div>
    <div id="libList" class="lib-list-view" style="display:none"></div>
    <div id="libEmpty" class="lib-empty" style="display:none">
      No SOPs match your filters. <button onclick="clearFilters()" class="link-btn">Clear filters</button>
    </div>
  </div>
</div>
"@

$libScripts = @"
<script>
const SOPS_LIB = $sopsJson;
let currentView = 'grid';
function statusClass(st) { return 'status-' + st.toLowerCase().replace(/\s+/g,'-'); }
function cardHTML(s) {
  const bm = isBookmarked(s.id);
  return '<div class="sop-card" data-id="' + s.id + '">' +
    '<div class="sop-card-top"><span class="sop-id-badge">' + s.id + '</span>' +
    '<button class="bookmark-btn' + (bm?' bookmarked':'') + '" data-bookmark="' + s.id + '" onclick="toggleBookmark(\'' + s.id + '\')" title="Bookmark" aria-label="Bookmark">' +
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg></button></div>' +
    '<h3 class="sop-card-title"><a href="reader/' + s.id + '.html">' + s.title + '</a></h3>' +
    '<p class="sop-card-desc">' + s.description.slice(0,130) + (s.description.length>130?'\u2026':'') + '</p>' +
    '<div class="sop-card-meta"><span class="meta-dept">' + s.department + '</span><span class="meta-ver">v' + s.version + '</span>' +
    '<span class="meta-status ' + statusClass(s.status) + '">' + s.status + '</span></div>' +
    '<div class="sop-card-footer"><span class="meta-date">Updated ' + s.updated + '</span>' +
    '<a class="card-read-btn" href="reader/' + s.id + '.html">Read \u2192</a></div></div>';
}
function rowHTML(s) {
  const bm = isBookmarked(s.id);
  return '<div class="lib-row" data-id="' + s.id + '">' +
    '<div class="lib-row-id"><span class="sop-id-badge">' + s.id + '</span></div>' +
    '<div class="lib-row-main"><a class="lib-row-title" href="reader/' + s.id + '.html">' + s.title + '</a>' +
    '<div class="lib-row-meta"><span class="meta-dept">' + s.department + '</span><span class="meta-ver">v' + s.version + '</span>' +
    '<span class="meta-status ' + statusClass(s.status) + '">' + s.status + '</span>' +
    '<span class="meta-date">Updated ' + s.updated + '</span><span class="meta-views">' + s.views + ' views</span></div></div>' +
    '<div class="lib-row-actions"><button class="bookmark-btn' + (bm?' bookmarked':'') + '" data-bookmark="' + s.id + '" onclick="toggleBookmark(\'' + s.id + '\')" title="Bookmark" aria-label="Bookmark">' +
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg></button>' +
    '<a class="card-read-btn" href="reader/' + s.id + '.html">Read \u2192</a></div></div>';
}
function getFilters() {
  return {
    q:      document.getElementById('libSearch').value.trim().toLowerCase(),
    dept:   document.querySelector('input[name="dept"]:checked')?.value || '',
    cat:    document.querySelector('input[name="cat"]:checked')?.value || '',
    status: document.querySelector('input[name="status"]:checked')?.value || '',
    owner:  document.querySelector('input[name="owner"]:checked')?.value || '',
    sort:   document.getElementById('sortSelect').value,
  };
}
function applyFilters() {
  const f = getFilters();
  let items = SOPS_LIB.filter(s => {
    if (f.dept   && s.department !== f.dept)   return false;
    if (f.cat    && s.category   !== f.cat)    return false;
    if (f.status && s.status     !== f.status) return false;
    if (f.owner  && s.owner      !== f.owner)  return false;
    if (f.q) {
      const hay = [s.id,s.title,s.department,s.description,...(s.tags||[])].join(' ').toLowerCase();
      if (!hay.includes(f.q)) return false;
    }
    return true;
  });
  if (f.sort === 'title')  items.sort((a,b) => a.title.localeCompare(b.title));
  else if (f.sort === 'views') items.sort((a,b) => b.views - a.views);
  else if (f.sort === 'id')   items.sort((a,b) => a.id.localeCompare(b.id));
  else items.sort((a,b) => b.updated.localeCompare(a.updated));
  document.getElementById('libCount').textContent = items.length + ' of ' + SOPS_LIB.length + ' SOPs';
  document.getElementById('libEmpty').style.display = items.length ? 'none' : '';
  document.getElementById('libGrid').innerHTML = items.map(cardHTML).join('');
  document.getElementById('libList').innerHTML = items.map(rowHTML).join('');
}
function setView(v) {
  currentView = v;
  document.getElementById('libGrid').style.display = v === 'grid' ? '' : 'none';
  document.getElementById('libList').style.display = v === 'list' ? '' : 'none';
  document.getElementById('btnGrid').classList.toggle('active', v === 'grid');
  document.getElementById('btnList').classList.toggle('active', v === 'list');
}
function clearFilters() {
  document.getElementById('libSearch').value = '';
  document.querySelectorAll('input[type="radio"]').forEach(r => { r.checked = r.value === ''; });
  document.getElementById('sortSelect').value = 'updated';
  applyFilters();
}
const params = new URLSearchParams(location.search);
if (params.has('dept')) {
  const d = params.get('dept');
  const r = document.querySelector('input[name="dept"][value="' + d + '"]');
  if (r) r.checked = true;
}
applyFilters();
</script>
"@

$libHtml = Get-PageHtml -title "SOP Library -- eLSOP" -depth "" -navActive "library" -content $libContent -scripts $libScripts
$libPath = Join-Path $SiteDir "library.html"
[System.IO.File]::WriteAllText($libPath, $libHtml, [System.Text.Encoding]::UTF8)
Write-Host "  wrote: site/library.html ($($sops.Count) SOPs)"

# ── Generate dashboard.html ───────────────────────────────────────────────────
Write-Host "Generating dashboard.html..."

# Compute stats
$deptCounts   = @{}
$statusCounts = @{}
$sops | ForEach-Object {
    $d = $_.department; if (-not $deptCounts[$d])   { $deptCounts[$d] = 0 };   $deptCounts[$d]++
    $s = $_.status;     if (-not $statusCounts[$s]) { $statusCounts[$s] = 0 }; $statusCounts[$s]++
}
$totalSOPs    = $sops.Count
$activeCount  = if ($statusCounts["Active"]) { $statusCounts["Active"] } else { 0 }
$pendingCount = if ($statusCounts["Pending Review"]) { $statusCounts["Pending Review"] } else { 0 }
$deptCount    = $deptCounts.Count

$topViewed = $sops | Sort-Object { [int]$_.views } -Descending | Select-Object -First 5
$recentUpd = $sops | Sort-Object { $_.updated } -Descending | Select-Object -First 5

$topViewedRows = ($topViewed | ForEach-Object {
    $t = EH $_.title
    "          <tr><td><a class=`"dash-sop-link`" href=`"reader/$($_.id).html`">$t</a><br><span class=`"dash-sop-id`">$($_.id)</span></td><td>$($_.department)</td><td><span class=`"views-badge`">$($_.views)</span></td></tr>"
}) -join "`n"

$recentRows = ($recentUpd | ForEach-Object {
    $t = EH $_.title
    "          <tr><td><a class=`"dash-sop-link`" href=`"reader/$($_.id).html`">$t</a><br><span class=`"dash-sop-id`">$($_.id)</span></td><td>v$($_.version)</td><td>$($_.updated)</td></tr>"
}) -join "`n"

$deptGroupsHtml = ""
foreach ($dept in ($deptCounts.Keys | Sort-Object)) {
    $deptSops = $sops | Where-Object { $_.department -eq $dept }
    $deptItems = ($deptSops | ForEach-Object {
        $t = EH $_.title
        $sc = StatusClass $_.status
        "        <a class=`"dept-sop-item`" href=`"reader/$($_.id).html`"><span class=`"sop-id-badge`">$($_.id)</span><span class=`"dept-sop-title`">$t</span><span class=`"meta-status $sc`">$($_.status)</span><span class=`"dept-sop-date`">$($_.updated)</span></a>"
    }) -join "`n"
    $deptGroupsHtml += @"

    <div class="dept-group">
      <div class="dept-group-header">$dept <span class="dept-group-count">$($deptSops.Count)</span></div>
      <div class="dept-sop-list">
$deptItems
      </div>
    </div>
"@
}

$deptLabelsJson = ($deptCounts.Keys | Sort-Object | ForEach-Object { '"' + $_ + '"' }) -join ","
$deptValuesJson = ($deptCounts.Keys | Sort-Object | ForEach-Object { $deptCounts[$_] }) -join ","
$statusLabelsJson = ($statusCounts.Keys | Sort-Object | ForEach-Object { '"' + $_ + '"' }) -join ","
$statusValuesJson = ($statusCounts.Keys | Sort-Object | ForEach-Object { $statusCounts[$_] }) -join ","

$dashContent = @"
<div class="dash-layout">
  <div class="dash-header">
    <h1 class="dash-title">Dashboard</h1>
    <p class="dash-sub">SOP metrics and activity overview</p>
  </div>
  <div class="kpi-grid">
    <div class="kpi-card"><div class="kpi-icon kpi-blue"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg></div><div class="kpi-body"><div class="kpi-num">$totalSOPs</div><div class="kpi-lbl">Total SOPs</div></div></div>
    <div class="kpi-card"><div class="kpi-icon kpi-green"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg></div><div class="kpi-body"><div class="kpi-num">$activeCount</div><div class="kpi-lbl">Active SOPs</div></div></div>
    <div class="kpi-card"><div class="kpi-icon kpi-orange"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg></div><div class="kpi-body"><div class="kpi-num">$pendingCount</div><div class="kpi-lbl">Pending Review</div></div></div>
    <div class="kpi-card"><div class="kpi-icon kpi-purple"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg></div><div class="kpi-body"><div class="kpi-num">$deptCount</div><div class="kpi-lbl">Departments</div></div></div>
  </div>
  <div class="dash-charts-row">
    <div class="dash-card dash-card-chart"><div class="dash-card-header">SOPs by Department</div><canvas id="deptChart" height="220"></canvas></div>
    <div class="dash-card dash-card-chart"><div class="dash-card-header">Status Distribution</div><canvas id="statusChart" height="220"></canvas></div>
  </div>
  <div class="dash-tables-row">
    <div class="dash-card">
      <div class="dash-card-header">Most Viewed SOPs</div>
      <table class="dash-table"><thead><tr><th>SOP</th><th>Department</th><th>Views</th></tr></thead>
      <tbody>$topViewedRows</tbody></table>
    </div>
    <div class="dash-card">
      <div class="dash-card-header">Recently Updated</div>
      <table class="dash-table"><thead><tr><th>SOP</th><th>Version</th><th>Updated</th></tr></thead>
      <tbody>$recentRows</tbody></table>
    </div>
  </div>
  <div class="dash-card" style="margin-top:24px;">
    <div class="dash-card-header">All SOPs by Department</div>
$deptGroupsHtml
  </div>
</div>
"@

$dashScripts = @"
<script>
function drawBarChart(canvasId, labels, values, color) {
  const canvas = document.getElementById(canvasId); if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.offsetWidth || 400, H = canvas.height || 220;
  canvas.width = W;
  const max = Math.max(...values, 1);
  const padL = 80, padR = 16, padT = 16, padB = 40;
  const barH = (H - padT - padB) / labels.length;
  ctx.clearRect(0,0,W,H);
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const textCol = isDark ? '#c9d1d9' : '#374151';
  const gridCol = isDark ? '#30363d' : '#e5e7eb';
  labels.forEach((lbl, i) => {
    const y = padT + i * barH;
    const barW = (values[i] / max) * (W - padL - padR);
    ctx.strokeStyle = gridCol; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(padL, y + barH/2); ctx.lineTo(W-padR, y+barH/2); ctx.stroke();
    ctx.fillStyle = color; ctx.fillRect(padL, y+barH*0.2, barW, barH*0.6);
    ctx.fillStyle = textCol; ctx.font = '12px system-ui,sans-serif'; ctx.textAlign = 'right';
    ctx.fillText(lbl, padL-6, y+barH/2+4);
    ctx.fillStyle = textCol; ctx.textAlign = 'left';
    ctx.fillText(values[i], padL+barW+6, y+barH/2+4);
  });
}
function drawPieChart(canvasId, labels, values) {
  const canvas = document.getElementById(canvasId); if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.offsetWidth || 400, H = canvas.height || 220;
  canvas.width = W;
  const total = values.reduce((a,b)=>a+b,0);
  const cx = W/2-60, cy = H/2, r = Math.min(cx,cy)-16;
  const colors = ['#3b82d4','#10b981','#f59e0b','#ef4444','#8b5cf6','#06b6d4'];
  let angle = -Math.PI/2;
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const textCol = isDark ? '#c9d1d9' : '#374151';
  ctx.clearRect(0,0,W,H);
  values.forEach((v,i) => {
    const sweep = (v/total)*2*Math.PI;
    ctx.beginPath(); ctx.moveTo(cx,cy); ctx.arc(cx,cy,r,angle,angle+sweep);
    ctx.closePath(); ctx.fillStyle = colors[i%colors.length]; ctx.fill();
    angle += sweep;
  });
  labels.forEach((lbl,i) => {
    const lx = W-120, ly = 20+i*24;
    ctx.fillStyle = colors[i%colors.length]; ctx.fillRect(lx,ly,12,12);
    ctx.fillStyle = textCol; ctx.font = '12px system-ui,sans-serif'; ctx.textAlign = 'left';
    ctx.fillText(lbl+' ('+values[i]+')', lx+18, ly+11);
  });
}
const deptLabels   = [$deptLabelsJson];
const deptValues   = [$deptValuesJson];
const statusLabels = [$statusLabelsJson];
const statusValues = [$statusValuesJson];
window.addEventListener('load', () => {
  drawBarChart('deptChart',   deptLabels,   deptValues,   '#3b82d4');
  drawPieChart('statusChart', statusLabels, statusValues);
});
document.getElementById('themeIcon')?.closest('button')?.addEventListener('click', () => {
  setTimeout(() => {
    drawBarChart('deptChart',   deptLabels,   deptValues,   '#3b82d4');
    drawPieChart('statusChart', statusLabels, statusValues);
  }, 50);
});
</script>
"@

$dashHtml = Get-PageHtml -title "Dashboard -- eLSOP" -depth "" -navActive "dash" -content $dashContent -scripts $dashScripts
$dashPath = Join-Path $SiteDir "dashboard.html"
[System.IO.File]::WriteAllText($dashPath, $dashHtml, [System.Text.Encoding]::UTF8)
Write-Host "  wrote: site/dashboard.html"

# ── Generate portal homepage (index.html) ────────────────────────────────────
Write-Host "Generating index.html (portal homepage)..."

$recentSops  = $sops | Sort-Object { $_.updated } -Descending | Select-Object -First 6
$homeDepts   = $sops | ForEach-Object { $_.department } | Sort-Object -Unique
$deptCountsHome = @{}
$sops | ForEach-Object { $d = $_.department; if (-not $deptCountsHome[$d]) { $deptCountsHome[$d]=0 }; $deptCountsHome[$d]++ }
$pendingCountHome = ($sops | Where-Object { $_.status -eq "Pending Review" }).Count
$deptIcons = @{ "Claims"="&#x1F4CB;"; "Compliance"="&#x2705;"; "Finance"="&#x1F4B0;"; "Operations"="&#x2699;&#xFE0F;"; "IT"="&#x1F4BB;"; "HR"="&#x1F465;" }

$deptCardsHtml = ($homeDepts | ForEach-Object {
    $dept = $_
    $icon = if ($deptIcons[$dept]) { $deptIcons[$dept] } else { "&#x1F4C1;" }
    $cnt  = $deptCountsHome[$dept]
    $dv   = [System.Uri]::EscapeDataString($dept)
    "      <a class=`"dept-card`" href=`"library.html?dept=$dv`"><span class=`"dept-icon`">$icon</span><span class=`"dept-name`">$dept</span><span class=`"dept-count`">$cnt SOPs</span></a>"
}) -join "`n"

$recentCardsHtml = ($recentSops | ForEach-Object {
    $s  = $_
    $st = EH $s.title
    $sd = EH $s.description
    $sc = StatusClass $s.status
    $changeHtml = ""
    if ($s.last_change) {
        $cd = EH $s.last_change.description
        $cdShort = if ($cd.Length -gt 80) { $cd.Substring(0,80) + "&#x2026;" } else { $cd }
        $changeHtml = "        <div class=`"sop-card-change`"><span class=`"change-dot`"></span><span class=`"change-desc`">$cdShort</span></div>"
    }
    $descShort = if ($sd.Length -gt 120) { $sd.Substring(0,120) + "&#x2026;" } else { $sd }
    "      <div class=`"sop-card`">`n        <div class=`"sop-card-top`"><span class=`"sop-id-badge`">$($s.id)</span><button class=`"bookmark-btn`" data-bookmark=`"$($s.id)`" onclick=`"toggleBookmark('$($s.id)')`" title=`"Bookmark`" aria-label=`"Bookmark`"><svg width=`"14`" height=`"14`" viewBox=`"0 0 24 24`" fill=`"currentColor`" stroke=`"currentColor`" stroke-width=`"2`"><path d=`"M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z`"/></svg></button></div>`n        <h3 class=`"sop-card-title`"><a href=`"reader/$($s.id).html`">$st</a></h3>`n        <p class=`"sop-card-desc`">$descShort</p>`n$changeHtml`n        <div class=`"sop-card-meta`"><span class=`"meta-dept`">$($s.department)</span><span class=`"meta-ver`">v$($s.version)</span><span class=`"meta-status $sc`">$($s.status)</span></div>`n        <div class=`"sop-card-footer`"><span class=`"meta-date`">Updated $($s.updated) &middot; $(EH $s.owner)</span><a class=`"card-read-btn`" href=`"reader/$($s.id).html`">Read &#x2192;</a></div>`n      </div>"
}) -join "`n"

$homeContent = @"
<section class="hero">
  <div class="hero-inner">
    <div class="hero-text">
      <h1 class="hero-title">eLSOP Knowledge Portal</h1>
      <p class="hero-sub">Your single source of truth for Standard Operating Procedures &#x2014; searchable, bookmarkable, always up to date.</p>
      <div class="hero-search-wrap">
        <svg class="hero-search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <input id="heroSearch" class="hero-search" type="text" placeholder="Search by title, SOP number, department&#x2026;" autocomplete="off">
        <div id="heroResults" class="hero-results" style="display:none"></div>
      </div>
    </div>
    <div class="hero-stats">
      <div class="stat-card"><span class="stat-num">$($sops.Count)</span><span class="stat-lbl">Total SOPs</span></div>
      <div class="stat-card"><span class="stat-num">$($homeDepts.Count)</span><span class="stat-lbl">Departments</span></div>
      <div class="stat-card"><span class="stat-num">$pendingCountHome</span><span class="stat-lbl">Pending Review</span></div>
      <div class="stat-card"><span class="stat-num">$($recentSops.Count)</span><span class="stat-lbl">Updated This Quarter</span></div>
    </div>
  </div>
</section>
<section class="home-section">
  <div class="home-section-inner">
    <h2 class="section-heading">Departments</h2>
    <div class="dept-grid">
$deptCardsHtml
    </div>
  </div>
</section>
<section class="home-section home-section-alt">
  <div class="home-section-inner">
    <div class="section-header-row">
      <h2 class="section-heading">Recently Updated</h2>
      <a class="section-link" href="library.html">View all &#x2192;</a>
    </div>
    <div class="card-grid">
$recentCardsHtml
    </div>
  </div>
</section>
<section class="home-section" id="bookmarksSection" style="display:none">
  <div class="home-section-inner">
    <div class="section-header-row">
      <h2 class="section-heading">&#x2B50; Your Bookmarks</h2>
      <button class="section-link" onclick="clearAllBookmarks()">Clear all</button>
    </div>
    <div class="card-grid" id="bookmarkGrid"></div>
  </div>
</section>
"@

$homeScripts = @"
<script>
const SOPS_DATA = $sopsJson;
const hs = document.getElementById('heroSearch');
const hr = document.getElementById('heroResults');
hs.addEventListener('input', function() {
  const q = this.value.trim().toLowerCase();
  if (!q) { hr.style.display='none'; return; }
  const hits = SOPS_DATA.filter(s =>
    s.title.toLowerCase().includes(q) || s.id.toLowerCase().includes(q) ||
    s.department.toLowerCase().includes(q) || (s.tags||[]).join(' ').toLowerCase().includes(q) ||
    s.description.toLowerCase().includes(q)
  ).slice(0,10);
  if (!hits.length) { hr.style.display='none'; return; }
  hr.innerHTML = hits.map(s => '<a class="hr-item" href="reader/'+s.id+'.html"><div class="hr-main"><span class="gr-id">'+s.id+'</span><span class="gr-title">'+s.title+'</span></div><span class="gr-dept">'+s.department+' &middot; v'+s.version+'</span></a>').join('');
  hr.style.display='block';
});
document.addEventListener('click', e => { if (!hs.contains(e.target) && !hr.contains(e.target)) hr.style.display='none'; });
function renderBookmarks() {
  const bm = getBookmarks();
  const section = document.getElementById('bookmarksSection');
  const grid = document.getElementById('bookmarkGrid');
  if (!bm.length) { section.style.display='none'; return; }
  section.style.display='';
  const items = SOPS_DATA.filter(s => bm.includes(s.id));
  grid.innerHTML = items.map(s =>
    '<div class="sop-card"><div class="sop-card-top"><span class="sop-id-badge">'+s.id+'</span><button class="bookmark-btn bookmarked" data-bookmark="'+s.id+'" onclick="toggleBookmark(\''+s.id+'\');renderBookmarks()" title="Remove bookmark" aria-label="Remove bookmark"><svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg></button></div><h3 class="sop-card-title"><a href="reader/'+s.id+'.html">'+s.title+'</a></h3><p class="sop-card-desc">'+s.description.slice(0,120)+(s.description.length>120?'\u2026':'')+'</p><div class="sop-card-footer"><span class="meta-date">Updated '+s.updated+'</span><a class="card-read-btn" href="reader/'+s.id+'.html">Read \u2192</a></div></div>'
  ).join('');
}
function clearAllBookmarks() { localStorage.removeItem('bookmarks'); renderBookmarks(); }
renderBookmarks();
</script>
"@

$homeHtml = Get-PageHtml -title "eLSOP Knowledge Portal" -depth "" -navActive "home" -content $homeContent -scripts $homeScripts
[System.IO.File]::WriteAllText((Join-Path $SiteDir "index.html"), $homeHtml, [System.Text.Encoding]::UTF8)
Write-Host "  wrote: site/index.html (portal homepage, $($sops.Count) SOPs)"

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "  Pages: index.html, library.html, dashboard.html + $($sops.Count) reader pages"
