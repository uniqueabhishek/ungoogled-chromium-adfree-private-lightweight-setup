# Imports every Google Chrome profile folder into Ungoogled Chromium.
# Each profile is named after its Gmail / Google address so it is easy to find in the picker.
# Run with BOTH browsers closed. Chrome itself is not changed.
# Anything already in Ungoogled Chromium is renamed to "*.before-import-<date>", never deleted.

$ErrorActionPreference = 'Stop'
$chrome   = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$chromium = "$env:LOCALAPPDATA\Chromium\User Data"

if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host 'Close Chrome and Ungoogled Chromium first, then run this again.' -ForegroundColor Yellow
    return
}

$stamp   = Get-Date -Format 'yyyyMMdd-HHmm'
$dstPath = Join-Path $chromium 'Local State'
$dst = if (Test-Path $dstPath) { Get-Content $dstPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
if (Test-Path $dstPath) { Copy-Item $dstPath "$dstPath.before-import-$stamp" }
if (-not $dst.profile) { $dst.profile = @{} }

# Caches are rebuilt by the browser, so skip them to save space and time.
$skipDirs = 'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache',
            'GrShaderCache', 'ShaderCache', 'CacheStorage', 'ScriptCache'

# Default first, then Profile N in number order.
$folders = Get-ChildItem $chrome -Directory |
    Where-Object { $_.Name -match '^(Default|Profile \d+)$' -and (Test-Path "$($_.FullName)\Preferences") } |
    Sort-Object { if ($_.Name -eq 'Default') { -1 } else { [int]($_.Name -replace '\D') } }

$infoCache = [ordered]@{}
foreach ($f in $folders) {
    $folder = $f.Name
    $prefs  = Get-Content "$($f.FullName)\Preferences" -Raw | ConvertFrom-Json -AsHashtable
    $email  = @($prefs.account_info | ForEach-Object { $_.email } | Where-Object { $_ })[0]
    $name   = if ($email) { $email } else { "$($prefs.profile.name) ($folder)" }
    $avatar = if ($null -ne $prefs.profile.avatar_index) { $prefs.profile.avatar_index } else { 26 }

    $to = Join-Path $chromium $folder
    if (Test-Path $to) { Rename-Item $to "$folder.before-import-$stamp" }
    Write-Host "Copying $name ($folder)..."
    robocopy $f.FullName $to /E /XD @skipDirs /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host '  Some files could not be copied.' -ForegroundColor Yellow }

    # Store the same name inside the profile, so the browser does not rename it back.
    $copiedPrefsPath = Join-Path $to 'Preferences'
    $copied = Get-Content $copiedPrefsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $copied.profile) { $copied.profile = @{} }
    $copied.profile.name = $name
    [IO.File]::WriteAllText($copiedPrefsPath, ($copied | ConvertTo-Json -Depth 100 -Compress))

    $infoCache[$folder] = [ordered]@{
        name                     = $name
        avatar_icon              = "chrome://theme/IDR_PROFILE_AVATAR_$avatar"
        is_using_default_name    = $false
        is_using_default_avatar  = $false
        is_ephemeral             = $false
        background_apps          = $false
        managed_user_id          = ''
    }
    # Show the Google profile photo Chrome saved in the profile folder.
    if (Test-Path "$to\Google Profile Picture.png") {
        $infoCache[$folder].gaia_picture_file_name  = 'Google Profile Picture.png'
        $infoCache[$folder].use_gaia_picture        = $true
        $infoCache[$folder].is_using_default_avatar = $true
    }
}

$dst.profile.info_cache             = $infoCache
$dst.profile.profiles_order         = @($infoCache.Keys)
$dst.profile.last_used              = 'Default'
$dst.profile.last_active_profiles   = @('Default')
$dst.profile.show_picker_on_startup = $true

[IO.File]::WriteAllText($dstPath, ($dst | ConvertTo-Json -Depth 100 -Compress))
Write-Host "Done - $($infoCache.Count) profiles imported. Open Ungoogled Chromium." -ForegroundColor Green
