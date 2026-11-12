#Requires -Version 7
# Makes Google (with live suggestions) the address-bar search engine in EVERY Ungoogled Chromium profile,
# and adds the shortcuts yt / gh / maps (type "yt cats", "gh react", "maps london") plus @bookmarks/@history/@tabs.
#
#   pwsh -ExecutionPolicy Bypass -File ".\Set-Search-Engine.ps1"
#
# Needs: uv and node on PATH. Closes Ungoogled Chromium, then reopens it with all windows and tabs restored.
# Backups of every changed file: "<file>.before-search-<date>" inside each profile folder.
#
# How it works (both halves are needed - see set_search_engine.py for why):
#   1. set_search_engine.py writes the Google + shortcut rows into each profile's "Web Data".
#   2. Making Google the DEFAULT lives in a tamper-protected setting, so the browser's own Settings code
#      has to do it: each profile's settings files are copied to a temporary folder, a hidden Chromium
#      opens them and switches the default (make-google-default.mjs), and the files are copied back.
#      (Chromium refuses remote control of the real profile folder, hence the temporary copy.)

$ErrorActionPreference = 'Stop'
$exe      = "$env:LOCALAPPDATA\Chromium\Application\chrome.exe"
$userData = "$env:LOCALAPPDATA\Chromium\User Data"
$work     = Join-Path $env:TEMP 'chromium-search-setup'
$files    = 'Preferences', 'Secure Preferences', 'Web Data', 'Web Data-journal'

function Get-Chromium { Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Chromium\*' } }

# Chrome and Chromium are both chrome.exe - only touch the one running from the Chromium folder.
$wasRunning = [bool](Get-Chromium)
if ($wasRunning) {
    Write-Host 'Closing Ungoogled Chromium (tabs are restored afterwards)...'
    Get-Chromium | Stop-Process -Force
    while (Get-Chromium) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Seconds 1
}

try {
    Write-Host "`n1. Adding Google and shortcuts to each profile" -ForegroundColor Cyan
    uv run --script "$PSScriptRoot\set_search_engine.py"
    if ($LASTEXITCODE -ne 0) { throw 'set_search_engine.py failed - nothing else was changed.' }

    Write-Host "`n2. Making Google the default in each profile" -ForegroundColor Cyan
    $ls = Get-Content "$userData\Local State" -Raw | ConvertFrom-Json -AsHashtable
    $profiles = @($ls.profile.info_cache.Keys)
    $ls_names = @{}; foreach ($p in $profiles) { $ls_names[$p] = $ls.profile.info_cache[$p].name }
    $ls.profile.info_cache = @{ Default = @{ name = 'setup' } }
    $ls.profile.last_used = 'Default'
    $ls.profile.last_active_profiles = @('Default')
    $failed = @()

    foreach ($p in $profiles) {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory "$work\Default" | Out-Null
        [IO.File]::WriteAllText("$work\Local State", ($ls | ConvertTo-Json -Depth 100 -Compress))
        foreach ($f in $files) { if (Test-Path "$userData\$p\$f") { Copy-Item "$userData\$p\$f" "$work\Default\$f" } }

        $proc = Start-Process $exe -PassThru -WindowStyle Hidden -ArgumentList '--headless=new', "--user-data-dir=`"$work`"",
            '--no-first-run', '--remote-debugging-port=9339', 'about:blank'
        $msg = node "$PSScriptRoot\make-google-default.mjs" 9339
        $ok = $LASTEXITCODE -eq 0
        Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match [regex]::Escape($work) } | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
        Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match [regex]::Escape($work) } | Stop-Process -Force

        if ($ok) {
            foreach ($f in 'Preferences', 'Secure Preferences', 'Web Data') { Copy-Item "$work\Default\$f" "$userData\$p\$f" -Force }
            Remove-Item "$userData\$p\Web Data-journal" -ErrorAction SilentlyContinue
            if (Test-Path "$work\Default\Web Data-journal") { Copy-Item "$work\Default\Web Data-journal" "$userData\$p\" }
        } else { $failed += $p }
        Write-Host ('  {0,-11} {1,-45} {2}' -f $p, $ls_names[$p], $msg)
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    # Name the profile, or Chromium opens the profile picker and restores nothing.
    $lastUsed = (Get-Content "$userData\Local State" -Raw | ConvertFrom-Json).profile.last_used
    if (-not $lastUsed) { $lastUsed = 'Default' }
    if ($wasRunning) { Start-Process $exe -ArgumentList "--profile-directory=`"$lastUsed`"", '--restore-last-session' }
}

if ($failed) { Write-Host "`nNot switched (left as they were): $($failed -join ', ')" -ForegroundColor Yellow }
else { Write-Host "`nDone. Type any words in the address bar - Google suggestions appear as you type." -ForegroundColor Green }
