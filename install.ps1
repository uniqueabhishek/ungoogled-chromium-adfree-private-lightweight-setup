# Ungoogled Chromium - ad-free, private setup for Windows 10 / 11
# https://github.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup
#
# Run it by pasting this one line into PowerShell (no admin needed):
#
#   irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/install.ps1 | iex
#
# What it does, in order:
#   1. Installs Ungoogled Chromium with winget (skipped if it is already installed)
#   2. Makes Google, with live suggestions, the search engine for new profiles
#   3. Adds a scheduled task that keeps the browser updated (weekly + at every sign-in)
#   4. Turns on AdGuard ad-blocking DNS and the flag that allows installing extensions
#   5. Sets browser policies: search suggestions, HTTPS first, page preloading, and the
#      uBlock Origin Lite settings ("Complete" mode + extra filter lists)
#   6. Downloads the Chromium Web Store helper extension
#   7. Opens the browser on the uBlock Origin Lite install page and the extensions page
#
# Everything is for the current Windows user only. Every browser file it changes is backed up
# first as "<file>.before-setup-<date>". Undo it all with uninstall.ps1 from the same repo.
# Works in Windows PowerShell 5.1 and PowerShell 7.

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar in 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$appDir   = "$env:LOCALAPPDATA\Chromium"          # settings, profiles, updater (always per user)
$userData = "$appDir\User Data"
# The browser program itself is per user normally, or in Program Files if it was installed for all users.
$exeCandidates = @("$appDir\Application\chrome.exe", "$env:ProgramFiles\Chromium\Application\chrome.exe",
                   "${env:ProgramFiles(x86)}\Chromium\Application\chrome.exe")
function Find-Exe { $exeCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1 }
$exe      = Find-Exe
$cwsDir   = "$appDir\Unpacked Extensions\Chromium Web Store"
$stamp    = Get-Date -Format 'yyyyMMdd-HHmm'
$adguard  = 'https://dns.adguard-dns.com/dns-query'
$uboLite  = 'ddkjiahejlhfcafbddmgiahcphecmpfh'
$policies = 'HKCU:\Software\Policies\Chromium'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Note($text) { Write-Host "   $text" }
function Warn($text) { Write-Host "   $text" -ForegroundColor Yellow }
function Backup($path) { if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path "$path.before-setup-$stamp" -Force } }
function Set-Prop($obj, $name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Get-Chromium { Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Chromium\Application\*' } }

$logFile = Join-Path $env:TEMP 'ungoogled-chromium-setup-log.txt'
try { Start-Transcript -Path $logFile -Force | Out-Null } catch { }
try {   # the whole setup; any unexpected error is reported at the bottom with the log file

Write-Host ''
Write-Host 'Ungoogled Chromium - ad-free, private setup' -ForegroundColor Green
Write-Host '-------------------------------------------'

# Chrome and Chromium are both chrome.exe, so only look at the one running from the Chromium folder.
if (Get-Chromium) {
    Warn 'Ungoogled Chromium is open. Close every window (and its icon near the clock), then run this again.'
    return
}

# ---------------------------------------------------------------------------------------------
Step '1. Install Ungoogled Chromium'
if ($exe) {
    Note "Already installed: version $((Get-Item $exe).VersionInfo.ProductVersion)"
} else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Warn 'winget (Windows "App Installer") is missing. Install or update "App Installer" from the'
        Warn 'Microsoft Store, then run this again:  ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
        return
    }
    $hadUserData = Test-Path -LiteralPath $userData
    Note 'Downloading and installing (about 1-2 minutes)...'
    # --scope user: install for this Windows user only (no admin), in %LOCALAPPDATA%\Chromium.
    winget install --id eloston.ungoogled-chromium -e --scope user --silent --accept-source-agreements --accept-package-agreements
    $exe = Find-Exe
    if (-not $exe) {
        Note 'Trying again without the per-user option...'
        winget install --id eloston.ungoogled-chromium -e --silent --accept-source-agreements --accept-package-agreements
        $exe = Find-Exe
    }
    if (-not $exe) { Warn 'The install did not finish (chrome.exe not found). Nothing else was changed.'; Warn "Log: $logFile"; return }
    Note "Installed version $((Get-Item $exe).VersionInfo.ProductVersion)"

    # The installer can open the browser by itself. Close it before changing settings, and if that
    # created a brand-new empty profile, remove it so the first real start picks up the settings below.
    Start-Sleep -Seconds 3
    if (Get-Chromium) {
        Get-Chromium | Stop-Process -Force -ErrorAction SilentlyContinue
        $t = 0; while ((Get-Chromium) -and $t -lt 30) { Start-Sleep -Milliseconds 500; $t++ }
        Start-Sleep -Seconds 1
        if (-not $hadUserData) { Remove-Item -LiteralPath $userData -Recurse -Force -ErrorAction SilentlyContinue }
        Note 'Closed the browser window the installer opened; it reopens at the end.'
    }
}
$exeDir = Split-Path $exe

# ---------------------------------------------------------------------------------------------
Step '2. Google search with suggestions (new profiles)'
# Ungoogled Chromium ships with no Google entry, and the search-engine policies are blocked on home
# PCs. "initial_preferences" next to chrome.exe is read whenever a profile is created, and sets the
# default engine there. A copy is kept in the Chromium folder so the updater can put it back.
$initialPrefs = @'
{
  "default_search_provider_data": {
    "template_url_data": {
      "short_name": "Google",
      "keyword": "google.com",
      "url": "https://www.google.com/search?q={searchTerms}&ie={inputEncoding}",
      "suggestions_url": "https://www.google.com/complete/search?client=chrome&q={searchTerms}",
      "favicon_url": "https://www.google.com/favicon.ico",
      "input_encodings": ["UTF-8"],
      "safe_for_autoreplace": false,
      "prepopulate_id": 0,
      "synced_guid": "7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e01"
    }
  },
  "search": { "suggest_enabled": true },
  "distribution": { "skip_first_run_ui": true, "suppress_first_run_default_browser_prompt": true }
}
'@
New-Item -ItemType Directory -Force $appDir | Out-Null
[IO.File]::WriteAllText("$appDir\initial_preferences", $initialPrefs)
$prefsPlaced = $true
try { Copy-Item "$appDir\initial_preferences" "$exeDir\initial_preferences" -Force }
catch { $prefsPlaced = $false }
$existing = @(Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue |
              Where-Object { Test-Path -LiteralPath "$($_.FullName)\Preferences" })
if (-not $prefsPlaced) {
    Warn "The browser is installed for all users in $exeDir, which needs admin rights to change."
    Warn 'Run this command once more from PowerShell opened with "Run as administrator" to set Google search.'
} elseif ($existing) {
    Note 'Done for new profiles. Your existing profiles keep their current search engine;'
    Note 'see "Already using Ungoogled Chromium?" in the README to switch them.'
} else {
    Note 'Done. The first profile will start with Google.'
}

# ---------------------------------------------------------------------------------------------
Step '3. Automatic updates'
# Ungoogled Chromium has no built-in updater (Chrome's is a Google service), so winget does it.
$updater = "$appDir\update-chromium.ps1"
$updaterBody = @'
# Keeps Ungoogled Chromium up to date. Run by the "Update Ungoogled Chromium" scheduled task.
$log = Join-Path $PSScriptRoot 'winget-upgrade.log'
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" | Add-Content $log
winget upgrade --id eloston.ungoogled-chromium -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 |
    Where-Object { $_ -match '\w{3,}' } | Add-Content $log
# Put the Google search default for new profiles back if the update removed it.
$keep = Join-Path $PSScriptRoot 'initial_preferences'
$live = Join-Path '__EXEDIR__' 'initial_preferences'
if ((Test-Path $keep) -and -not (Test-Path $live)) { Copy-Item $keep $live -ErrorAction SilentlyContinue }
# Keep the log short.
$lines = @(Get-Content $log); if ($lines.Count -gt 400) { $lines[-400..-1] | Set-Content $log }
'@
$updaterBody = $updaterBody.Replace('__EXEDIR__', $exeDir.Replace("'", "''"))
[IO.File]::WriteAllText($updater, $updaterBody)
try {
    $ps       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action   = New-ScheduledTaskAction -Execute $ps `
                -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updater`""
    $triggers = @(
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At 1pm
        New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    )
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'Update Ungoogled Chromium' -Action $action -Trigger $triggers -Settings $settings -Force | Out-Null
    Note 'Task "Update Ungoogled Chromium" added: Wednesdays at 1 pm and at every sign-in.'
} catch {
    Warn "Could not add the update task: $($_.Exception.Message)"
    Warn 'Update by hand now and then with:  winget upgrade --id eloston.ungoogled-chromium -e'
}

# ---------------------------------------------------------------------------------------------
Step '4. Ad-blocking DNS and extension install flag'
New-Item -ItemType Directory -Force $userData | Out-Null
$lsPath = Join-Path $userData 'Local State'
$ls = $null
if (Test-Path -LiteralPath $lsPath) {
    try { $ls = Get-Content -LiteralPath $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $ls = $null }
    if (-not $ls) { Warn "Could not read $lsPath - skipped. Set these by hand (see docs/GUIDE.md, sections 4.1 and 4.3)." }
} else {
    $ls = New-Object psobject
}
if ($ls) {
    Backup $lsPath
    Set-Prop $ls 'dns_over_https' ([pscustomobject]@{ mode = 'secure'; templates = $adguard })
    if (-not $ls.PSObject.Properties['browser']) { Set-Prop $ls 'browser' (New-Object psobject) }
    $flags = @($ls.browser.enabled_labs_experiments | Where-Object { $_ -and $_ -notlike 'extension-mime-request-handling@*' })
    Set-Prop $ls.browser 'enabled_labs_experiments' ([object[]]($flags + 'extension-mime-request-handling@2'))
    [IO.File]::WriteAllText($lsPath, ($ls | ConvertTo-Json -Depth 100 -Compress))
    Note "Secure DNS: AdGuard ($adguard)"
    Note 'Flag: "Handling of extension MIME type requests" = Always prompt for install'
}

# ---------------------------------------------------------------------------------------------
Step '5. Browser policies'
# "Recommended" = a default you can still change in Settings. "Mandatory" = fixed.
# These make the browser menu say "Managed by your organization"; that is expected.
$recommended = "$policies\Recommended"
New-Item -Path $recommended -Force | Out-Null      # also creates the parent key
New-ItemProperty $recommended -Name SearchSuggestEnabled     -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty $recommended -Name NetworkPredictionOptions -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty $policies    -Name HttpsOnlyMode -Value 'force_balanced_enabled' -PropertyType String -Force | Out-Null
Note 'Search suggestions on, typed addresses try HTTPS first, likely pages preloaded.'

# uBlock Origin Lite reads its settings from this policy key (its "managed storage").
$ubo = "$policies\3rdparty\extensions\$uboLite\policy"
New-Item -Path $ubo -Force | Out-Null
New-ItemProperty $ubo -Name defaultFiltering -Value 'complete' -PropertyType String -Force | Out-Null
$rulesets = @(
    '+adguard-mobile'                                    # Ads: AdGuard/uBO mobile ads
    '+adguard-spyware-url', '+block-lan'                 # Privacy: tracking codes in links, LAN probing
    '+annoyances-cookies', '+annoyances-overlays',       # Annoyances: cookie banners, pop-ups...
    '+annoyances-notifications', '+annoyances-others'
)
# Add the local ad list for the country set in Windows (Settings > Time & language > Region).
$regional = @{
    al='alb-0'; xk='alb-0'; eg='ara-0'; sa='ara-0'; ma='ara-0'; dz='ara-0'; bg='bgr-0'; cn='chn-0'; tw='chn-0'
    cz='cze-0'; sk='cze-0'; de='deu-0'; ch='deu-0'; at='deu-0'; ee='est-0'; fi='fin-0'; fr='fra-0'; be='fra-0'
    gr='grc-0'; cy='grc-0'; hr='hrv-0'; rs='hrv-0'; hu='hun-0'; id='idn-0'; my='idn-0'; in='ind-0'; lk='ind-0'
    np='ind-0'; ir='irn-0'; is='isl-0'; il='isr-0'; it='ita-0'; jp='jpn-1'; kr='kor-1'; lt='ltu-0'; lv='lva-0'
    mk='mkd-0'; nl='nld-0'; no='nor-0'; dk='nor-0'; pl='pol-0'; ro='rou-1'; md='rou-1'; ru='rus-0'; uz='rus-0'
    kz='rus-0'; es='spa-0'; ar='spa-0'; mx='spa-0'; co='spa-0'; br='spa-1'; pt='spa-1'; si='svn-0'; se='swe-1'
    th='tha-0'; tr='tur-0'; ua='ukr-0'; vn='vie-1'
}
try {
    $country = [string](Get-ItemProperty 'HKCU:\Control Panel\International\Geo' -ErrorAction Stop).Name
    if ($country -and $regional.ContainsKey($country.ToLower())) { $rulesets += '+' + $regional[$country.ToLower()] }
} catch { }
Remove-Item "$ubo\rulesets" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path "$ubo\rulesets" -Force | Out-Null
for ($i = 0; $i -lt $rulesets.Count; $i++) {
    New-ItemProperty "$ubo\rulesets" -Name ($i + 1) -Value $rulesets[$i] -PropertyType String -Force | Out-Null
}
Note 'uBlock Origin Lite: "Complete" filtering + extra lists for ads, privacy and annoyances.'

# ---------------------------------------------------------------------------------------------
Step '6. Chromium Web Store helper'
# Brings back "Add to Chromium" on the Chrome Web Store and keeps extensions updated.
try {
    $release = Invoke-RestMethod 'https://api.github.com/repos/NeverDecaf/chromium-web-store/releases/latest' -UseBasicParsing
    $asset   = $release.assets | Where-Object name -like '*.crx' | Select-Object -First 1
    $crx     = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $crx -UseBasicParsing
    if (Test-Path -LiteralPath $cwsDir) { Rename-Item -LiteralPath $cwsDir "Chromium Web Store.before-setup-$stamp" }
    New-Item -ItemType Directory -Force $cwsDir | Out-Null
    tar -xf $crx -C $cwsDir 2>$null
    Remove-Item $crx -ErrorAction SilentlyContinue
    if (-not (Test-Path "$cwsDir\manifest.json")) { throw 'unpacking failed' }
    Note "Chromium Web Store $($release.tag_name) is ready in:"
    Note "  $cwsDir"
} catch {
    Warn "Could not get Chromium Web Store ($($_.Exception.Message)). See docs/GUIDE.md, section 5, to add it by hand."
}

# ---------------------------------------------------------------------------------------------
Step '7. Opening the browser'
$major  = (Get-Item $exe).VersionInfo.ProductMajorPart
$uboUrl = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=$major.0&acceptformat=crx2,crx3&x=id%3D$uboLite%26uc"
Start-Process $exe -ArgumentList $uboUrl, 'chrome://extensions'
try { Set-Clipboard -Value $cwsDir } catch { }

Write-Host ''
Write-Host 'Almost done - three clicks left in the browser:' -ForegroundColor Green
Write-Host '  1. uBlock Origin Lite tab: click "Add extension".'
Write-Host '  2. Extensions tab: turn on "Developer mode" (top right), click "Load unpacked", click the'
Write-Host '     folder bar at the top of the window, press Ctrl+V, Enter, then "Select Folder".'
Write-Host '     (The folder path is already copied for you.)'
Write-Host '  3. Click the puzzle icon in the toolbar and pin uBlock Origin Lite.'
Write-Host ''
Write-Host 'Recommended: chrome://extensions > uBlock Origin Lite > Details > turn on "Allow User Scripts"'
Write-Host '(better blocking on YouTube) and "Allow in Incognito".'
Write-Host 'Undo everything later with uninstall.ps1 - see the README.'
Write-Host ''
} catch {
    Write-Host ''
    Warn "Setup stopped: $($_.Exception.Message)"
    Warn "Nothing is broken - run the same command again. If it stops again, send this file: $logFile"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
}
