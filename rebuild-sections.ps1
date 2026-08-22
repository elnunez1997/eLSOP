# rebuild-sections.ps1
# Reads every DOCX in site/sops, extracts real headings + content,
# and patches sops.json sections accordingly.
# Run from eLSOP repo root: powershell.exe -ExecutionPolicy Bypass -File rebuild-sections.ps1

param([string]$Root = "")
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = (Get-Location).Path }

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-DocxSections($path) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" }
    $stream = $entry.Open()
    $reader = New-Object System.IO.StreamReader($stream)
    $xml = $reader.ReadToEnd()
    $reader.Close(); $zip.Dispose()
    [xml]$doc = $xml
    $mgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $mgr.AddNamespace("w","http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $sections = [System.Collections.Generic.List[hashtable]]::new()
    $currentHeading = $null
    $currentLines   = [System.Collections.Generic.List[string]]::new()
    foreach ($para in $doc.SelectNodes("//w:body/w:p", $mgr)) {
        $styleNode = $para.SelectSingleNode("w:pPr/w:pStyle/@w:val", $mgr)
        $isHeading = $styleNode -and $styleNode.Value -match "^Heading"
        $runs = $para.SelectNodes(".//w:t", $mgr)
        $text = ($runs | ForEach-Object { $_.InnerText }) -join ""
        if ($isHeading) {
            if ($null -ne $currentHeading) {
                $sections.Add(@{ heading = $currentHeading; content = ($currentLines -join "`n") })
            }
            $currentHeading = $text.Trim()
            $currentLines   = [System.Collections.Generic.List[string]]::new()
        } elseif ($null -ne $currentHeading -and $text.Trim()) {
            $currentLines.Add($text.Trim())
        }
    }
    if ($null -ne $currentHeading) {
        $sections.Add(@{ heading = $currentHeading; content = ($currentLines -join "`n") })
    }
    return $sections
}

function Heading-To-Id($h) {
    $u = $h.ToUpper().Trim()
    if ($u -match "DEDUCTION TYPE")                            { return "deduction_types" }
    if ($u -match "CUSTOMER GENERAL")                          { return "customer_general_info" }
    if ($u -match "INDIRECT INFO")                             { return "indirect_info" }
    if ($u -match "BACKUP RETRIEVAL")                          { return "backup_retrieval" }
    if ($u -match "CLIENT SPEC.*VALID|CLIENT VALID.*SPEC|CLIENT SPECIFIC$|CLIENT SPECIFICS|CLIENT VALIDATION") { return "client_specific" }
    if ($u -match "PROCESS STEPS")                             { return "process_steps" }
    if ($u -match "BPS TEAM")                                  { return "bps_team" }
    if ($u -match "CURRENT VERSION|^VERSION HISTORY")          { return "version_history" }
    if ($u -match "COMPLETE VERSION")                          { return "complete_version_history" }
    if ($u -match "WORK INSTRUCTIONS")                         { return "work_instructions" }
    if ($u -match "ADVANTAGE|BILL PAYER")                      { return "advantage_program" }
    if ($u -match "IN-AD COUPON")                              { return "in_ad_coupon" }
    # fallback slug
    return ($u.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
}

# Headings to exclude (doc boilerplate, not useful content sections)
# Also skip version history headings - they may contain false-positive credential patterns
$SKIP = @("WORK INSTRUCTIONS","COMPLETE VERSION HISTORY","CURRENT VERSION HISTORY","VERSION HISTORY")

# Build lookup: docx filename -> extracted sections array
$sopSopSections = @{}
$sopDir = Join-Path $Root "site\sops"
Get-ChildItem $sopDir | Where-Object { $_.Extension -eq ".docx" } | ForEach-Object {
    $secs = Get-DocxSections $_.FullName
    $out = @()
    foreach ($s in $secs) {
        if ($SKIP -contains $s.heading.ToUpper().Trim()) { continue }
        $id = Heading-To-Id $s.heading
        $out += [ordered]@{
            id      = $id
            title   = $s.heading
            content = $s.content
        }
    }
    $sopSopSections[$_.Name] = $out
    Write-Host "  Parsed $($_.Name): $($out.Count) sections"
}

# Load sops.json
$sopsPath = Join-Path $Root "data\sops.json"
$sops = Get-Content $sopsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$updated = 0
foreach ($sop in $sops) {
    if (-not $sop.file) { continue }
    # Extract just the filename from the path e.g. "sops/Foo.docx" -> "Foo.docx"
    $fname = Split-Path $sop.file -Leaf
    if (-not $sopSopSections.ContainsKey($fname)) {
        Write-Host "  SKIP $($sop.id) - no DOCX match for $fname" -ForegroundColor Yellow
        continue
    }
    $newSections = $sopSopSections[$fname]
    if ($newSections.Count -eq 0) { continue }

    # Replace sections with real extracted ones
    $sop.sections = $newSections
    $updated++
    Write-Host "  Updated $($sop.id) ($($sop.title)): $($newSections.Count) sections" -ForegroundColor Green
}

# Write back
$json = $sops | ConvertTo-Json -Depth 10 -Compress:$false
[System.IO.File]::WriteAllText($sopsPath, $json, [System.Text.Encoding]::UTF8)
Write-Host ""
Write-Host "Done. Updated $updated SOPs in sops.json." -ForegroundColor Cyan
