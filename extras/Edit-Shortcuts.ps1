# Adds, removes or lists the shortcuts on Ungoogled Chromium's new tab page.
# Needed because the browser hides the "Add shortcut" button when the search engine is not Google.
#
#   .\Edit-Shortcuts.ps1                                         list every profile and its shortcuts
#   .\Edit-Shortcuts.ps1 -Profile abc@gmail.com -Add GitHub https://github.com/
#   .\Edit-Shortcuts.ps1 -Profile abc@gmail.com -Remove GitHub
#
# -Profile takes the name shown in the profile picker (the Gmail address) or the folder name (Default, Profile 6).
# Adding or removing needs Ungoogled Chromium closed. A profile can hold at most 10 shortcuts.

param(
    [string]$Profile,
    [string]$Add,
    [string]$Url,
    [string]$Remove
)

$ErrorActionPreference = 'Stop'
$chromium  = "$env:LOCALAPPDATA\Chromium\User Data"
$maxLinks  = 10
$infoCache = (Get-Content (Join-Path $chromium 'Local State') -Raw | ConvertFrom-Json -AsHashtable).profile.info_cache

function Read-Prefs($folder) {
    Get-Content (Join-Path $chromium "$folder\Preferences") -Raw | ConvertFrom-Json -AsHashtable
}

# No profile given: list everything and stop.
if (-not $Profile) {
    foreach ($folder in $infoCache.Keys) {
        $links = @((Read-Prefs $folder).custom_links.list | Where-Object { $_ })
        Write-Host "$($infoCache[$folder].name)  [$folder]  $($links.Count)/$maxLinks" -ForegroundColor Cyan
        foreach ($l in $links) { Write-Host "    $($l.title)  -  $($l.url)" }
    }
    return
}

$folder = @($infoCache.Keys | Where-Object { $_ -eq $Profile -or $infoCache[$_].name -eq $Profile })[0]
if (-not $folder) { Write-Host "No profile named '$Profile'. Run the script with no options to see the names." -ForegroundColor Yellow; return }

if (-not $Add -and -not $Remove) { Write-Host 'Say what to do: -Add <title> -Url <address>, or -Remove <title>.' -ForegroundColor Yellow; return }

# Chrome and Chromium are both chrome.exe, so only stop for the one running from the Chromium folder.
if (Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Chromium\*' }) {
    Write-Host 'Close Ungoogled Chromium first, then run this again.' -ForegroundColor Yellow
    return
}

$prefsPath = Join-Path $chromium "$folder\Preferences"
$prefs = Read-Prefs $folder
if (-not $prefs.custom_links) { $prefs.custom_links = @{} }
$links = [Collections.Generic.List[object]]@($prefs.custom_links.list | Where-Object { $_ })

if ($Add) {
    if (-not $Url) { Write-Host 'Give the address too: -Url https://...' -ForegroundColor Yellow; return }
    if ($Url -notmatch '^[a-z]+://') { $Url = "https://$Url" }
    if ($links | Where-Object { $_.url -eq $Url }) { Write-Host "$Url is already a shortcut." -ForegroundColor Yellow; return }
    if ($links.Count -ge $maxLinks) { Write-Host "This profile already has $maxLinks shortcuts. Remove one first." -ForegroundColor Yellow; return }
    $links.Add([ordered]@{ isMostVisited = $false; title = $Add; url = $Url })
    Write-Host "Added $Add ($Url)." -ForegroundColor Green
}

if ($Remove) {
    $match = @($links | Where-Object { $_.title -eq $Remove -or $_.url -eq $Remove })
    if (-not $match) { Write-Host "No shortcut called '$Remove'." -ForegroundColor Yellow; return }
    foreach ($m in $match) { [void]$links.Remove($m) }
    Write-Host "Removed $Remove." -ForegroundColor Green
}

Copy-Item $prefsPath "$prefsPath.before-shortcuts" -Force
$prefs.custom_links.list        = @($links)
$prefs.custom_links.initialized = $true
[IO.File]::WriteAllText($prefsPath, ($prefs | ConvertTo-Json -Depth 100 -Compress))
Write-Host "$($infoCache[$folder].name) now has $($links.Count)/$maxLinks shortcuts."
