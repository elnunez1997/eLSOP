$content = Get-Content "data/sops.json" -Raw
try {
    $parsed = $content | ConvertFrom-Json
    Write-Host ("VALID - " + $parsed.Count + " SOPs")
    foreach ($sop in $parsed) {
        Write-Host ("  " + $sop.id + " - " + $sop.title)
    }
} catch {
    Write-Host ("INVALID JSON: " + $_.Exception.Message)
}
