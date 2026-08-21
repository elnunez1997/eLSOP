# build-data.ps1
# Reads Customer_Matrix.xlsx via the already-dumped JSON and writes customers.js

param(
    [string]$DumpDir = "C:\Users\eLNunez\.bob\playground\.bob\tmp\xlsx-dumps\Customer_Matrix-c9bef6aa028386e2",
    [string]$OutFile = "C:\Users\eLNunez\.bob\playground\eLSOP\site\customers.js"
)

$json = Get-Content "$DumpDir/Customer_SOP_Matrix.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$rows = $json.rows

# Formal SOP doc filenames
$formalSOPs = @{
    "ADUSA"                     = "ADUSA_Distr_The_Giant_Company_Giant_Foods_Stop_Shop.docx"
    "ASSOCIATED FOOD STORE"     = "Associated_Food_Stores_AFS.docx"
    "ASSOCIATED SUPERMARKET"    = "Associated_Supermarket_Group.docx"
    "ASSOCIATED WHOLESALE"      = "Associated_Wholesale_Grocers_AWG_Valu_Merchandisers_VMC.docx"
    "AWG"                       = "Associated_Wholesale_Grocers_AWG_Valu_Merchandisers_VMC.docx"
    "VALU MERCHANDISERS"        = "Associated_Wholesale_Grocers_AWG_Valu_Merchandisers_VMC.docx"
    "BROOKSHIRE GROCERY"        = "Brookshire_Grocery_Company.docx"
    "CERTCO"                    = "Certco_Inc_Woodmans_Janesville.docx"
    "WOODMAN"                   = "Certco_Inc_Woodmans_Janesville.docx"
    "CORE-MARK"                 = "Core_Mark.docx"
    "CORE MARK"                 = "Core_Mark.docx"
    "CS WHOLESALE"              = "CS_Wholesale_Grocers_Inc.docx"
    "C&S WHOLESALE"             = "CS_Wholesale_Grocers_Inc.docx"
    "WINN-DIXIE"                = "CS-Winn_Dixie-BiLo_Holdings.docx"
    "WINN DIXIE"                = "CS-Winn_Dixie-BiLo_Holdings.docx"
    "BI-LO"                     = "CS-Winn_Dixie-BiLo_Holdings.docx"
    "BILO"                      = "CS-Winn_Dixie-BiLo_Holdings.docx"
    "CVS"                       = "CVS_Distribution_Peoples_Drug.docx"
    "PEOPLES DRUG"              = "CVS_Distribution_Peoples_Drug.docx"
    "DELHAIZE"                  = "Delhaize.docx"
    "DEMOULAS"                  = "Demoulas_Supermarkets_Inc.docx"
    "MARKET BASKET"             = "Demoulas_Supermarkets_Inc.docx"
    "FAREWAY"                   = "Fareway_Stores_Inc.docx"
    "GENERAL TRADING"           = "General_Trading.docx"
    "GOLUB"                     = "Golub_Corporation.docx"
    "PRICE CHOPPER"             = "Golub_Corporation.docx"
    "MARKET 32"                 = "Golub_Corporation.docx"
    "H E BUTT"                  = "H_E_Butt_Grocery_Company.docx"
    "H-E-B"                     = "H_E_Butt_Grocery_Company.docx"
    "HEB "                      = "H_E_Butt_Grocery_Company.docx"
    "HARRIS TEETER"             = "Harris_Teeter_Supermarkets.docx"
    "HYVEE"                     = "HyVee_Corporate_Lomar_Perishable_Dist_of_Iowa_PDI.docx"
    "HY-VEE"                    = "HyVee_Corporate_Lomar_Perishable_Dist_of_Iowa_PDI.docx"
    "LOMAR"                     = "HyVee_Corporate_Lomar_Perishable_Dist_of_Iowa_PDI.docx"
    "PERISHABLE DISTRIBUTORS"   = "HyVee_Corporate_Lomar_Perishable_Dist_of_Iowa_PDI.docx"
    "INGLES"                    = "Ingles_Supermarkets.docx"
    "JETRO"                     = "Jetro_Restaurant_Depot.docx"
    "RESTAURANT DEPOT"          = "Jetro_Restaurant_Depot.docx"
    "KROGER"                    = "Kroger_Ralphs_Grocery_Company_Jakes_Finer_Foods_Vitacostcom.docx"
    "K V A T"                   = "K_V_A_T_Food_Store_Inc.docx"
    "MCLANE"                    = "McLane_Company_Inc.docx"
    "MERCHANTS DISTRIBUTORS"    = "Merchants_Distributors_LLC.docx"
    "MITCHELL GROCERY"          = "Mitchell_Grocery_Company.docx"
    "OK GROCERY"                = "OK_Grocery_Co_Giant_Eagle.docx"
    "GIANT EAGLE"               = "OK_Grocery_Co_Giant_Eagle.docx"
    "PUBLIX"                    = "Publix_Super_Markets_Inc.docx"
    "RETAIL MARKETING GROUP"    = "Retail_Marketing_Group.docx"
    "SAVE MART"                 = "Save_Mart_Yosemite_Save_Mart_Food_Maxx.docx"
    "FOOD MAXX"                 = "Save_Mart_Yosemite_Save_Mart_Food_Maxx.docx"
    "SCHNUCKS"                  = "Schnucks_Markets_Inc.docx"
    "SMART AND FINAL"           = "Smart_and_Final.docx"
    "SMART & FINAL"             = "Smart_and_Final.docx"
    "SPARTAN STORES"            = "Spartan_Stores_Inc_Nash_Finch.docx"
    "NASH FINCH"                = "Spartan_Stores_Inc_Nash_Finch.docx"
    "STATER"                    = "Stater_Bros.doc"
    "TOPS MARKETS"              = "Tops_Markets.docx"
    "TOPS FRIENDLY"             = "Tops_Markets.docx"
    "UNFI CONVENTIONAL"         = "UNFI_Conventional.docx"
    "UNITED NATURAL FOODS WEST" = "United_Natural_Foods_West_UNFI_Accounts_Payable.docx"
    "URM STORES"                = "URM_Spokane.docx"
    "URM SPOKANE"               = "URM_Spokane.docx"
    "WAKEFERN"                  = "Wakefern_Corporation.docx"
    "SHOPRITE"                  = "Wakefern_Corporation.docx"
    "SHOP RITE"                 = "Wakefern_Corporation.docx"
    "WEIS MARKETS"              = "Weis_Markets.docx"
    "WINCO"                     = "Winco_Foods_Inc.docx"
}

$customers = @()

foreach ($row in $rows) {
    $name   = if ($row[0]) { $row[0].ToString().Trim() } else { "" }
    $signon = if ($row[1]) { $row[1].ToString().Trim() } else { "" }
    $claims = if ($row[3]) { $row[3].ToString().Trim() } else { "" }

    if (-not $name) { continue }
    if ($name -match "Customer Name") { continue }

    # Detect formal SOP file first (some header rows have "Customer Signon Listing"
    # as their signon but ARE the canonical entry for a formal SOP customer)
    $sopFile = $null
    $nameUpper = $name.ToUpper()
    foreach ($key in $formalSOPs.Keys) {
        if ($nameUpper -match [regex]::Escape($key)) {
            $sopFile = $formalSOPs[$key]
            break
        }
    }

    # Skip pure header/divider rows that have no sop and no useful signon
    if ($signon -eq "Customer Signon Listing" -and -not $sopFile) { continue }

    $type    = if ($row[2]) { $row[2].ToString().Trim() } else { "" }
    $client  = if ($row[4]) { $row[4].ToString().Trim() } else { "" }
    $linelvl = if ($row[5]) { $row[5].ToString().Trim() } else { "" }
    $backup  = if ($row[6]) { $row[6].ToString().Trim() } else { "" }
    $updated = if ($row[7]) { $row[7].ToString().Substring(0,10) } else { "" }

    $customers += [PSCustomObject]@{
        name    = $name -replace '\s+', ' '
        signon  = $signon
        type    = $type
        claims  = $claims
        client  = $client
        linelvl = $linelvl
        backup  = $backup
        updated = $updated
        sop     = $sopFile
    }
}

$jsContent = "const CUSTOMERS = " + ($customers | ConvertTo-Json -Depth 3 -Compress) + ";"
Set-Content -Path $OutFile -Value $jsContent -Encoding UTF8
Write-Host "Written $($customers.Count) ACOSTA customers to $OutFile"
