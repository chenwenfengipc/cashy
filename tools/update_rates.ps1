# Writes rates.json for the Cashy app. Run it monthly (or whenever you like),
# then upload the file to your website at the address set in
# lib/services/rates_service.dart (RatesService.ratesUrl).
#
#   powershell -File tools\update_rates.ps1
#   powershell -File tools\update_rates.ps1 -Out C:\site\cashy\rates.json
#
# Rates come from the free Frankfurter API (European Central Bank reference
# rates). The app reads: base, date, and rates (how many of each currency one
# unit of `base` buys).
param(
    [string]$Out = "rates.json",
    [string]$Base = "USD"
)

$symbols = "MYR,SGD,CNY,IDR,JPY,THB,EUR,INR,USD" -split "," | Where-Object { $_ -ne $Base }
$uri = "https://api.frankfurter.dev/v1/latest?base=$Base&symbols=$($symbols -join ',')"
$r = Invoke-RestMethod -Uri $uri -TimeoutSec 30

$json = [ordered]@{
    version = 1
    base    = $r.base
    date    = $r.date
    rates   = $r.rates
} | ConvertTo-Json -Depth 4

# UTF-8 without a byte-order mark.
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) $Out),
    $json,
    (New-Object System.Text.UTF8Encoding $false))
Write-Host "Wrote $Out (rates as of $($r.date))"
