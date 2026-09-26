# Deploy multiple LWC bundles in one Metadata API request (faster than per-bundle loops).
# Usage from FIMBY/ (where sfdx-project.json lives):
#   .\scripts\deploy-lwc-bundles.ps1 fimbyUniversalHeader fimbyBottomNavigation
# Or pass a here-string list via -Bundles @('a','b')

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Bundles
)

if (-not $Bundles -or $Bundles.Count -eq 0) {
    Write-Error "Pass bundle API names, e.g. .\scripts\deploy-lwc-bundles.ps1 fimbyUniversalHeader fimbyModalShell"
    exit 1
}

$base = "force-app/main/default/lwc"
$args = @('project', 'deploy', 'start', '--wait', '10')
foreach ($b in $Bundles) {
    $path = Join-Path $base $b
    if (-not (Test-Path $path)) {
        Write-Error "Missing bundle folder: $path"
        exit 1
    }
    $args += '--source-dir'
    $args += $path
}

Write-Host "Deploying $($Bundles.Count) LWC bundle(s) in one request..."
& sf @args 2>&1 | Select-Object -Last 25
