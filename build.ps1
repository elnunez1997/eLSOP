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

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "  $($sops.Count) reader pages written to site/reader/"
