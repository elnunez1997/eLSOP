$DumpDir = 'C:\Users\eLNunez\.bob\playground\.bob\tmp\xlsx-dumps\Customer_Matrix-c9bef6aa028386e2'
$OutFile  = 'C:\Users\eLNunez\.bob\playground\eLSOP\site\customers.js'

$json = Get-Content "$DumpDir\Customer_SOP_Matrix.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$rows = $json.rows

$formalSOPs = @{
    'ADUSA'                     = 'ADUSA_Distr_The_Giant_Company_Giant_Foods_Stop_Shop.zip'
    'ASSOCIATED SUPERMARKET'    = 'Associated_Supermarket_Group.docx'
    'BROOKSHIRE GROCERY'        = 'Brookshire_Grocery_Company.docx'
    'DELHAIZE'                  = 'Delhaize.docx'
    'DEMOULAS'                  = 'Demoulas_Supermarkets_Inc.docx'
    'GENERAL TRADING'           = 'General_Trading.docx'
    'GOLUB'                     = 'Golub_Corporation.docx'
    'HARRIS TEETER'             = 'Harris_Teeter_Supermarkets.docx'
    'HYVEE'                     = 'HyVee_Corporate_Lomar_Perishable_Dist_of_Iowa_PDI.docx'
    'KROGER'                    = 'Kroger_Ralphs_Grocery_Company_Jakes_Finer_Foods_Vitacostcom.zip'
    'K V A T'                   = 'K_V_A_T_Food_Store_Inc.docx'
    'MCLANE'                    = 'McLane_Company_Inc.docx'
    'MITCHELL GROCERY'          = 'Mitchell_Grocery_Company.docx'
    'OK GROCERY'                = 'OK_Grocery_Co_Giant_Eagle.docx'
    'SAVE MART'                 = 'Save_Mart_Yosemite_Save_Mart_Food_Maxx.docx'
    'SCHNUCKS'                  = 'Schnucks_Markets_Inc.docx'
    'SMART AND FINAL'           = 'Smart_and_Final.docx'
    'STATER'                    = 'Stater_Bros.doc'
    'UNFI CONVENTIONAL'         = 'UNFI_Conventional.docx'
    'UNITED NATURAL FOODS WEST' = 'United_Natural_Foods_West_UNFI_Accounts_Payable.docx'
    'WINCO'                     = 'Winco_Foods_Inc.docx'
}

$customers = @()
$skipped   = 0
$included  = 0

foreach ($row in $rows) {
    $name   = if ($row[0]) { $row[0].ToString().Trim() -replace '\s+', ' ' } else { '' }
    $signon = if ($row[1]) { $row[1].ToString().Trim() } else { '' }
    $claims = if ($row[3]) { $row[3].ToString().Trim() } else { '' }

    if (-not $name) { $skipped++; continue }
    if ($name -match '^Customer Name') { continue }
    if ($signon -eq 'Customer Signon Listing') { $skipped++; continue }
    if ($claims -match '^See (formal |AWG )?SOP in ACOSTA Relay') { $skipped++; continue }

    $type    = if ($row[2]) { $row[2].ToString().Trim() } else { '' }
    $client  = if ($row[4]) { $row[4].ToString().Trim() } else { '' }
    $linelvl = if ($row[5]) { $row[5].ToString().Trim() } else { '' }
    $backup  = if ($row[6]) { $row[6].ToString().Trim() } else { '' }
    $updated = if ($row[7]) { $row[7].ToString().Substring(0, [Math]::Min(10, $row[7].ToString().Length)) } else { '' }

    $sopFile   = ''
    $nameUpper = $name.ToUpper()
    foreach ($key in $formalSOPs.Keys) {
        if ($nameUpper -match [regex]::Escape($key)) { $sopFile = $formalSOPs[$key]; break }
    }

    $customers += [PSCustomObject]@{
        name    = $name
        signon  = $signon
        type    = $type
        claims  = $claims
        client  = $client
        linelvl = $linelvl
        backup  = $backup
        updated = $updated
        sop     = $sopFile
    }
    $included++
}

$jsContent = 'const CUSTOMERS = ' + ($customers | ConvertTo-Json -Depth 3 -Compress) + ';'
Set-Content -Path $OutFile -Value $jsContent -Encoding UTF8
Write-Host "Included : $included ACOSTA customers"
Write-Host "Skipped  : $skipped non-ACOSTA rows"
Write-Host "File size: $([math]::Round((Get-Item $OutFile).Length / 1KB, 1)) KB"
