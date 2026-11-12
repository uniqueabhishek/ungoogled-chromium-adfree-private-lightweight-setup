# Undoes what install.ps1 set up. Your profiles, bookmarks and history are kept.
#
#   irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/uninstall.ps1 | iex
#
# Removes: the browser policies, the uBlock Origin Lite policy settings, the update task and script,
# the Google default for new profiles, and the AdGuard DNS + extension flag.
# It does NOT uninstall the browser itself. To remove that too, afterwards run:
#   winget uninstall --id eloston.ungoogled-chromium
# (and delete %LOCALAPPDATA%\Chromium if you also want the profiles gone).

& {
$ErrorActionPreference = 'Stop'
$appDir   = "$env:LOCALAPPDATA\Chromium"
$lsPath   = "$appDir\User Data\Local State"
$policies = 'HKCU:\Software\Policies\Chromium'
$stamp    = Get-Date -Format 'yyyyMMdd-HHmm'

if (Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Chromium\Application\*' }) {
    Write-Host 'Close Ungoogled Chromium first (including its icon near the clock), then run this again.' -ForegroundColor Yellow
    return
}

# Policies set by install.ps1 (other policies you may have added yourself are left alone).
Remove-ItemProperty "$policies\Recommended" -Name SearchSuggestEnabled, NetworkPredictionOptions -ErrorAction SilentlyContinue
Remove-ItemProperty $policies -Name HttpsOnlyMode -ErrorAction SilentlyContinue
Remove-Item "$policies\3rdparty\extensions\ddkjiahejlhfcafbddmgiahcphecmpfh" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Removed the browser policies.'

Unregister-ScheduledTask -TaskName 'Update Ungoogled Chromium' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item "$appDir\update-chromium.ps1", "$appDir\winget-upgrade.log" -ErrorAction SilentlyContinue
Write-Host 'Removed the update task.'

Remove-Item "$appDir\initial_preferences", "$appDir\Application\initial_preferences" -ErrorAction SilentlyContinue
Write-Host 'Removed the Google default for new profiles (existing profiles keep their search engine).'

if (Test-Path -LiteralPath $lsPath) {
    try {
        $ls = Get-Content -LiteralPath $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Copy-Item -LiteralPath $lsPath "$lsPath.before-uninstall-$stamp" -Force
        if ($ls.PSObject.Properties['dns_over_https']) { $ls.PSObject.Properties.Remove('dns_over_https') }
        if ($ls.browser -and $ls.browser.PSObject.Properties['enabled_labs_experiments']) {
            $ls.browser.enabled_labs_experiments = [object[]]@($ls.browser.enabled_labs_experiments |
                Where-Object { $_ -notlike 'extension-mime-request-handling@*' })
        }
        [IO.File]::WriteAllText($lsPath, ($ls | ConvertTo-Json -Depth 100 -Compress))
        Write-Host 'Turned off AdGuard DNS and the extension install flag.'
    } catch {
        Write-Host "Could not edit Local State ($($_.Exception.Message)). Turn off secure DNS in chrome://settings/security by hand." -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Done. Extensions stay installed; remove them at chrome://extensions if you want.' -ForegroundColor Green
Write-Host 'The Chromium Web Store folder is in:'
Write-Host "  $appDir\Unpacked Extensions\Chromium Web Store"
}
