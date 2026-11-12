param([string]$udd)
$ErrorActionPreference = 'SilentlyContinue'
while ($true) {
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($udd) })
  $out = @($procs | ForEach-Object {
    $t = 'browser'
    if ($_.CommandLine -match '--type=([\w-]+)') { $t = $Matches[1] }
    if ($t -eq 'utility' -and $_.CommandLine -match '--utility-sub-type=([\w\.-]+)') { $t = 'utility:' + $Matches[1] }
    [pscustomobject]@{ pid = [int]$_.ProcessId; cpu = ([double]$_.KernelModeTime + [double]$_.UserModeTime) / 1e7; ws = [double]$_.WorkingSetSize; priv = [double]$_.PrivatePageCount; type = $t }
  })
  [Console]::Out.WriteLine((ConvertTo-Json -Compress -Depth 3 -InputObject @{ procs = $out }))
  [Console]::Out.Flush()
  Start-Sleep -Milliseconds 900
}
