# Triggers a Discover cache refresh on the ONLINE backend.
# Reads NEXT_PUBLIC_API_URL + REFRESH_TOKEN from the repo-root .env (never prints the token).
# The backend scrapes in the background for a few minutes - check the app afterwards.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$lines = Get-Content -LiteralPath (Join-Path $root '.env')
$get = { param($n) ($lines | Where-Object { $_ -match "^\s*$n\s*=" } | ForEach-Object { ($_ -split '=', 2)[1].Trim().Trim('"').Trim("'") } | Select-Object -First 1) }
$url = ((& $get 'NEXT_PUBLIC_API_URL').TrimEnd('/'))
$token = (& $get 'REFRESH_TOKEN')
if ([string]::IsNullOrWhiteSpace($token)) { $token = (& $get 'DISCOVER_REFRESH_TOKEN') }
if ([string]::IsNullOrWhiteSpace($url)) { Write-Output '[ERROR] NEXT_PUBLIC_API_URL not found in .env'; exit 1 }
if ([string]::IsNullOrWhiteSpace($token)) { Write-Output '[ERROR] REFRESH_TOKEN not found in .env'; exit 1 }
Write-Output "[INFO] POST $url/refresh-discover ..."
curl.exe -s -m 30 -X POST "$url/refresh-discover" -H 'Content-Type: application/json' -H "X-Admin-Token: $token" -d '{}'
Write-Output ''
