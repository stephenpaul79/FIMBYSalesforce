# Deploy only git-changed LWC bundles (one --source-dir per bundle, batched).
$ErrorActionPreference = 'Continue'
$sfProject = 'c:\Users\srathjen\FIMBY\FIMBY'
$base = Join-Path $sfProject 'force-app\main\default\lwc'
$gitRoot = 'c:\Users\srathjen\FIMBY'

Push-Location $sfProject

$bundles = git -C $gitRoot diff --name-only HEAD -- 'FIMBY/force-app/main/default/lwc' |
    ForEach-Object { if ($_ -match 'FIMBY/force-app/main/default/lwc/([^/]+)/') { $matches[1] } } |
    Sort-Object -Unique |
    Where-Object {
        $js = Join-Path $base "$_\$_.js"
        $alt = Join-Path $base "$_\appLogoutRedirect.js"
        (Test-Path $js) -or (Test-Path $alt)
    }

Write-Host "Deploying $($bundles.Count) changed bundles in batches of 12..."
$batchSize = 12
$batchNum = 0
$failed = @()

for ($i = 0; $i -lt $bundles.Count; $i += $batchSize) {
    $end = [Math]::Min($i + $batchSize - 1, $bundles.Count - 1)
    $batch = @($bundles[$i..$end])
    $batchNum++
    $argList = @('project', 'deploy', 'start', '--wait', '10')
    foreach ($b in $batch) {
        $argList += '--source-dir'
        $argList += (Join-Path $base $b).Replace('\', '/')
    }
    Write-Host "`n--- Batch $batchNum ($($batch.Count) bundles) ---"
    $out = & sf @argList 2>&1
    $out | Select-Object -Last 10 | ForEach-Object { Write-Host $_ }
    $joined = $out | Out-String
    if ($LASTEXITCODE -ne 0 -and $joined -notmatch 'Missing message metadata.transfer:Finalizing' -and $joined -notmatch 'Status: Succeeded') {
        $failed += "Batch $batchNum"
    }
}

Pop-Location
if ($failed.Count -gt 0) {
    Write-Host "Failed batches: $($failed -join ', ')"
    exit 1
}
Write-Host 'All batches complete.'
