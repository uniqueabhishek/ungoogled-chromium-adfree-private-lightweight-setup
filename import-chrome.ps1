# Ungoogled Chromium - import your Google Chrome profiles
# https://github.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup
#
# Run install.ps1 first, then paste this one line into PowerShell:
#
#   irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/import-chrome.ps1 | iex
#
# For every Chrome profile it brings across: bookmarks, history, typed-address suggestions,
# open tabs, new tab shortcuts and the profile name. Each profile gets the search engine chosen during the install.
# Saved passwords are optional and guided: it opens Chrome's Export page and Ungoogled Chromium's
# Import page, finds the exported file, and deletes it afterwards.
# It does not bring: website logins (Chrome locks them; sign in once per site) or extensions
# (install them again from the Chrome Web Store).
#
# Chrome itself is never changed. Anything it would overwrite in Ungoogled Chromium is moved to
# "User Data\Backup before import <date>" first, never deleted. Works in Windows PowerShell 5.1 and 7.

& {
$ErrorActionPreference = 'Stop'
$appDir     = "$env:LOCALAPPDATA\Chromium"
$userData   = if ($env:UCS_USERDATA) { $env:UCS_USERDATA } else { "$appDir\User Data" }
$chromeData = if ($env:UCS_CHROMEDATA) { $env:UCS_CHROMEDATA } else { "$env:LOCALAPPDATA\Google\Chrome\User Data" }
$exe        = if ($env:UCS_EXE) { $env:UCS_EXE } else {
    @("$appDir\Application\chrome.exe", "$env:ProgramFiles\Chromium\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Chromium\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
$googleGuid = '7f0c5a2e-3b1d-4e6a-9c8f-0a1b2c3d4e01'
$stamp      = Get-Date -Format 'yyyyMMdd-HHmm'
$backupDir  = Join-Path $userData "Backup before import $stamp"
$logFile    = Join-Path $env:TEMP 'ungoogled-chromium-import-log.txt'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Note($text) { Write-Host "   $text" }
function Warn($text) { Write-Host "   $text" -ForegroundColor Yellow }
function Set-Prop($obj, $name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Read-Json($path) { try { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }
function Write-Json($path, $obj) { [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 100 -Compress)) }
function Get-Running($folderPart) { Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*\$folderPart\Application\*" } }
function Get-OurBrowser { Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } }

try { Start-Transcript -Path $logFile -Force | Out-Null } catch { }
try {

Write-Host ''
Write-Host 'Ungoogled Chromium - import Chrome profiles' -ForegroundColor Green
Write-Host '-------------------------------------------'

if (-not $exe) { Warn 'Ungoogled Chromium is not installed. Run the install command first (see the README).'; return }
$initialPrefs = Join-Path (Split-Path $exe) 'initial_preferences'
if (-not (Test-Path $initialPrefs)) {
    if (Test-Path "$appDir\initial_preferences") { try { Copy-Item "$appDir\initial_preferences" $initialPrefs } catch { } }
    if (-not (Test-Path $initialPrefs)) { Warn 'Run the install command first (see the README), then run this again.'; return }
}
if (-not (Test-Path -LiteralPath $chromeData)) { Warn "No Google Chrome profiles found in $chromeData."; return }
$anyOpen = { (-not $env:UCS_EXE -and ((Get-Running 'Google\Chrome') -or (Get-Running 'Chromium'))) -or (Get-OurBrowser) }
if (& $anyOpen) {
    $yn = if ([Environment]::UserInteractive) { Read-Host '   Google Chrome and/or Ungoogled Chromium is open. Close them now? Save anything you are working on first. (Y/N)' } else { 'n' }
    if ($yn -notmatch '^\s*y') { Warn 'Close Google Chrome AND Ungoogled Chromium (and their icons near the clock), then run this again.'; return }
    $open = { @(Get-Running 'Google\Chrome') + @(Get-Running 'Chromium') + @(Get-OurBrowser) | Where-Object { $_ } }
    & $open | ForEach-Object { try { [void]$_.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 20 -and (& $anyOpen); $i++) { Start-Sleep -Milliseconds 250 }
    & $open | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (& $anyOpen); $i++) { Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1
    if (& $anyOpen) { Warn 'Could not close the browsers. Close them yourself, then run this again.'; return }
    Note 'Closed the browsers.'
}

# ---------------------------------------------------------------------------------------------
Step '1. Finding your Chrome profiles'
$chromeLS = Read-Json (Join-Path $chromeData 'Local State')
$folders = @(Get-ChildItem -LiteralPath $chromeData -Directory |
    Where-Object { $_.Name -match '^(Default|Profile \d+)$' -and (Test-Path -LiteralPath "$($_.FullName)\Preferences") } |
    Sort-Object { if ($_.Name -eq 'Default') { -1 } else { [int]($_.Name -replace '\D') } })
if (-not $folders) { Warn 'No Chrome profiles found.'; return }

$plan = foreach ($f in $folders) {
    $info  = if ($chromeLS -and $chromeLS.profile.info_cache) { $chromeLS.profile.info_cache.($f.Name) } else { $null }
    $email = if ($info) { $info.user_name } else { '' }
    $label = if ($info -and $info.name) { $info.name } else { $f.Name }
    $name  = if ($email) { $email } elseif ($label -ne $f.Name) { $label } else { "Chrome $($f.Name)" }
    $avatarIdx = 26
    if ($info -and $info.avatar_icon -match 'IDR_PROFILE_AVATAR_(\d+)') { $avatarIdx = [int]$Matches[1] }
    [pscustomobject]@{ Folder = $f.Name; Source = $f.FullName; Name = $name; Avatar = $avatarIdx }
}
foreach ($p in $plan) { Note ("{0,-11} {1}" -f $p.Folder, $p.Name) }

# ---------------------------------------------------------------------------------------------
Step '2. Preparing a Chromium profile for each (with your search engine)'
# The search engine can only be set on a brand-new profile, when the browser starts for the first time.
# So each missing profile is made that way: start the browser once, hidden, as a first run, then
# move the new profile into place. Profiles that already exist keep their own settings.
New-Item -ItemType Directory -Force $userData | Out-Null
$firstRun = Join-Path $userData 'First Run'
$lsPath   = Join-Path $userData 'Local State'
$hadFirstRun = Test-Path -LiteralPath $firstRun
$parked = $null
if (Test-Path -LiteralPath "$userData\Default") {
    $parked = "Default.parked-$stamp"
    Rename-Item -LiteralPath "$userData\Default" $parked
}
try {
    foreach ($p in $plan) {
        $target = Join-Path $userData $p.Folder
        $exists = if ($p.Folder -eq 'Default') { [bool]$parked } else { Test-Path -LiteralPath $target }
        if ($exists) { Note "$($p.Folder): already in Ungoogled Chromium - adding Chrome's data to it."; continue }

        Remove-Item -LiteralPath $firstRun -Force -ErrorAction SilentlyContinue
        $proc = Start-Process $exe -PassThru -ArgumentList "--user-data-dir=`"$userData`"", '--window-position=-32000,-32000',
                '--no-default-browser-check', 'about:blank'
        $ok = $false
        for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
            Start-Sleep -Milliseconds 500
            $prefs = "$userData\Default\Preferences"
            if ((Test-Path -LiteralPath $prefs) -and (Test-Path -LiteralPath "$userData\Default\Web Data")) {
                $ok = (Get-Content -LiteralPath $prefs -Raw) -match $googleGuid
            }
        }
        Start-Sleep -Seconds 3
        Get-OurBrowser | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 40 -and (Get-OurBrowser); $i++) { Start-Sleep -Milliseconds 250 }
        Start-Sleep -Seconds 1
        if (-not (Test-Path -LiteralPath "$userData\Default")) { throw "the browser did not create a profile for $($p.Folder)" }
        if ($p.Folder -ne 'Default') { Rename-Item -LiteralPath "$userData\Default" $p.Folder }
        if ($ok) { Note "$($p.Folder): new profile with your search engine." }
        else     { Warn "$($p.Folder): new profile made, but the search engine could not be set on it." }
    }
} finally {
    # Put the original Default profile back, and the first-run marker.
    if ($parked) {
        if (Test-Path -LiteralPath "$userData\Default") {
            # Only possible if Chrome's Default was not imported; keep both.
            Rename-Item -LiteralPath "$userData\Default" "Default.extra-$stamp" -ErrorAction SilentlyContinue
        }
        Rename-Item -LiteralPath "$userData\$parked" 'Default'
    }
    if (-not (Test-Path -LiteralPath $firstRun)) { New-Item -ItemType File $firstRun | Out-Null }
}

# ---------------------------------------------------------------------------------------------
Step '3. Copying bookmarks, history, open tabs and shortcuts'
# Everything except: caches (rebuilt by the browser), settings files that hold the search engine,
# extension folders (Chrome's extensions do not run here), and files locked to Chrome
# (passwords, cookies), which would be unreadable.
$skipDirs  = 'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache',
             'ShaderCache', 'CacheStorage', 'ScriptCache', 'Service Worker', 'Network', 'Extensions',
             'Local Extension Settings', 'Sync Extension Settings', 'Managed Extension Settings', 'Extension Rules',
             'Extension Scripts', 'Extension State', 'DNR Extension Rules', 'Storage', 'blob_storage', 'Safe Browsing Network', 'optimization_guide_hint_cache_store',
             'optimization_guide_model_store', 'Download Service', 'GCM Store', 'Sync Data', 'Feature Engagement Tracker'
$skipFiles = 'Preferences', 'Secure Preferences', 'Web Data', 'Web Data-journal', 'Login Data', 'Login Data-journal',
             'Login Data For Account', 'Login Data For Account-journal', 'Cookies', 'Cookies-journal', 'LOCK', 'lockfile',
             'Account Web Data', 'Account Web Data-journal', 'Extension Cookies', 'Extension Cookies-journal', 'trusted_vault.pb', 'Google Profile Picture.png'
foreach ($p in $plan) {
    $target = Join-Path $userData $p.Folder
    # Move aside anything that would be overwritten.
    $incoming = Get-ChildItem -LiteralPath $p.Source -Force | Where-Object {
        ($_.PSIsContainer -and $skipDirs -notcontains $_.Name) -or (-not $_.PSIsContainer -and $skipFiles -notcontains $_.Name) }
    foreach ($item in $incoming) {
        $existing = Join-Path $target $item.Name
        if (Test-Path -LiteralPath $existing) {
            $bk = Join-Path $backupDir $p.Folder
            New-Item -ItemType Directory -Force $bk | Out-Null
            Move-Item -LiteralPath $existing (Join-Path $bk $item.Name) -Force
        }
    }
    Note "Copying $($p.Name)..."
    $rcArgs = @($p.Source, $target, '/E', '/XD') + $skipDirs + @('/XF') + $skipFiles + @('/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    & robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { Warn '  Some files could not be copied (they may be in use).' }

    # Profile name and new tab shortcuts go into the Chromium profile's own settings file.
    $tp = Join-Path $target 'Preferences'
    $prefs = Read-Json $tp
    if ($prefs) {
        if (-not $prefs.PSObject.Properties['profile']) { Set-Prop $prefs 'profile' (New-Object psobject) }
        Set-Prop $prefs.profile 'name' $p.Name
        $src = Read-Json (Join-Path $p.Source 'Preferences')
        if ($src -and $src.PSObject.Properties['custom_links']) { Set-Prop $prefs 'custom_links' $src.custom_links }
        Set-Prop $prefs.profile 'exit_type' 'Normal'
        Write-Json $tp $prefs
    }
}

# ---------------------------------------------------------------------------------------------
Step '4. Adding the profiles to the profile picker'
$ls = Read-Json $lsPath
if (-not $ls) { $ls = New-Object psobject }
if (-not $ls.PSObject.Properties['profile']) { Set-Prop $ls 'profile' (New-Object psobject) }
if (-not $ls.profile.PSObject.Properties['info_cache']) { Set-Prop $ls.profile 'info_cache' (New-Object psobject) }
foreach ($p in $plan) {
    $entry = $ls.profile.info_cache.($p.Folder)
    if (-not $entry) { $entry = New-Object psobject; Set-Prop $ls.profile.info_cache $p.Folder $entry }
    Set-Prop $entry 'name' $p.Name
    Set-Prop $entry 'avatar_icon' "chrome://theme/IDR_PROFILE_AVATAR_$($p.Avatar)"
    Set-Prop $entry 'is_using_default_name' $false
    Set-Prop $entry 'is_using_default_avatar' $false
    Set-Prop $entry 'is_ephemeral' $false
}
$order = @($ls.profile.info_cache.PSObject.Properties.Name |
    Where-Object { Test-Path -LiteralPath (Join-Path $userData $_) } |
    Sort-Object { if ($_ -eq 'Default') { -1 } else { [int]($_ -replace '\D') } })
foreach ($n in @($ls.profile.info_cache.PSObject.Properties.Name)) {
    if ($order -notcontains $n) { $ls.profile.info_cache.PSObject.Properties.Remove($n) }
}
Set-Prop $ls.profile 'profiles_order' ([object[]]$order)
Set-Prop $ls.profile 'last_used' 'Default'
Set-Prop $ls.profile 'show_picker_on_startup' ($order.Count -gt 1)
Write-Json $lsPath $ls
Note "$($order.Count) profile(s) in the picker."

# ---------------------------------------------------------------------------------------------
Step '5. Saved passwords (optional, guided)'
# Chrome locks its password file to itself, so passwords go through Chrome's own Export button and
# Ungoogled Chromium's own Import button. This step opens both pages, finds the exported file, and
# deletes it afterwards (it holds every password in plain text).
$chromeExe = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
               "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$canAsk = [Environment]::UserInteractive -and -not $env:UCS_EXE
if (-not $chromeExe -or -not $canAsk) {
    Note 'Skipped. To move passwords by hand, see "Saved passwords" in the README.'
} else {
    $answer = Read-Host '   Import saved passwords too? (Y/N)'
    if ($answer -notmatch '^\s*y') {
        Note 'Skipped. You can run this command again later to do it.'
    } else {
        $downloads = $null
        try { $downloads = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}' } catch { }
        $watch = @($downloads, "$env:USERPROFILE\Downloads", [Environment]::GetFolderPath('MyDocuments'),
                   [Environment]::GetFolderPath('Desktop')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
        foreach ($p in $plan) {
            Write-Host ''
            $yn = Read-Host "   Passwords for '$($p.Name)'? (Y/N)"
            if ($yn -notmatch '^\s*y') { continue }
            $since = (Get-Date).AddSeconds(-5)
            Start-Process $chromeExe -ArgumentList "--profile-directory=`"$($p.Folder)`"", 'chrome://password-manager/settings'
            Write-Host '   In GOOGLE CHROME (Password Manager > Settings): find "Export passwords" and click its' -ForegroundColor Green
            Write-Host '   "Download file" button, enter your Windows PIN if asked, then click Save.' -ForegroundColor Green
            Write-Host '   No "Export passwords" row? Your passwords are kept in your Google account instead: open'
            Write-Host '   passwords.google.com in Chrome, sign in, click the gear icon > "Export passwords" > Export.'
            Write-Host '   Waiting for the file... (press Ctrl+C to stop)'
            $csv = $null
            for ($i = 0; $i -lt 600 -and -not $csv; $i++) {
                Start-Sleep -Seconds 1
                $csv = Get-ChildItem -LiteralPath $watch -Filter '*Password*.csv' -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.LastWriteTime -gt $since -and $_.Length -gt 0 } |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            }
            if (-not $csv) { Warn 'No exported file appeared within 10 minutes - skipped.'; continue }
            Start-Sleep -Seconds 1
            Note "Found it: $($csv.Name)"
            try { Set-Clipboard -Value $csv.FullName } catch { }
            Start-Process $exe -ArgumentList "--profile-directory=`"$($p.Folder)`"", 'chrome://password-manager/settings'
            Write-Host '   In UNGOOGLED CHROMIUM: find "Import passwords", click "Select file", press Ctrl+V in the' -ForegroundColor Green
            Write-Host '   "File name" box (the path is copied for you), then Open.'
            Read-Host '   Press Enter here once it says the passwords were imported' | Out-Null
            # Overwrite, then delete (not to the Recycle Bin) - the file holds every password in plain text.
            try {
                $len = (Get-Item -LiteralPath $csv.FullName).Length
                [IO.File]::WriteAllBytes($csv.FullName, (New-Object byte[] $len))
                Remove-Item -LiteralPath $csv.FullName -Force
                Note 'The exported password file was deleted.'
            } catch { Warn "Could not delete $($csv.FullName) - delete it yourself and empty the Recycle Bin." }
            try { Set-Clipboard -Value ' ' } catch { }
        }
        Note 'Tip: also keep your passwords in a password manager such as Bitwarden - this browser has no sync.'
    }
}

Write-Host ''
Write-Host "Done - $(@($plan).Count) Chrome profile(s) imported." -ForegroundColor Green
Write-Host 'Open Ungoogled Chromium; with more than one profile it shows a profile picker.'
$major = (Get-Item $exe).VersionInfo.ProductMajorPart
Write-Host 'Extensions are per profile. In each profile that is NEW in Ungoogled Chromium, paste this into the'
Write-Host 'address bar once and click "Add extension" to get uBlock Origin Lite:'
Write-Host "  https://clients2.google.com/service/update2/crx?response=redirect&prodversion=$major.0&acceptformat=crx2,crx3&x=id%3Dddkjiahejlhfcafbddmgiahcphecmpfh%26uc"
if (Test-Path -LiteralPath $backupDir) { Write-Host "Files that were replaced are kept in: $backupDir" }
Write-Host ''
} catch {
    Write-Host ''
    Warn "Import stopped: $($_.Exception.Message)"
    Warn "Chrome was not changed. Send this file if you need help: $logFile"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
}
