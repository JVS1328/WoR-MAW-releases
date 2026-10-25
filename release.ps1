# Publishes a new MAW version for the WoR Mod Manager. See README.md.
#   .\release.ps1 1.3.4 -DraftChangelog   fill changelog.txt from the MAW commits since the last release, then edit it
#   .\release.ps1 1.3.4 -DryRun           check paks, size, game build and freshness without uploading
#   .\release.ps1 1.3.4                   publish
#   -Prerelease  publish a test release players don't get     -Force  skip the "nothing new / stale build" checks
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$DraftChangelog,
    [switch]$DryRun,
    [switch]$Prerelease,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$Name   = 'MAW'
$Repo   = 'JVS1328/WoR-MAW-releases'
$Source = Join-Path $PSScriptRoot '..\WoR-MAW'
$PakDir = Join-Path $Source 'out'
$Prefix = 'z_maw_'

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.3.4 (got '$Version')." }
$Tag = "v$Version"
$changelog = Join-Path $PSScriptRoot 'changelog.txt'
$builtFromFile = Join-Path $PSScriptRoot 'built-from.txt'   # source commit the last release was built from

# Native-command stderr would trip 'Stop' in Windows PowerShell, so git/gh calls check $LASTEXITCODE instead.
function Invoke-Native([scriptblock]$cmd) { $ErrorActionPreference = 'Continue'; & $cmd }
$head = (Invoke-Native { git -C $Source rev-parse HEAD }).Trim()
$lastBuiltFrom = if (Test-Path $builtFromFile) { (Get-Content $builtFromFile -TotalCount 1).Trim() } else { $null }

if ($DraftChangelog) {
    $range = if ($lastBuiltFrom) { "$lastBuiltFrom..HEAD" } else { 'HEAD' }
    $subjects = @(Invoke-Native { git -C $Source log --no-merges --format='- %s' $range })
    if ($subjects.Count -eq 0) { Write-Warning "No $Name commits since the last release ($lastBuiltFrom)." }
    @("$Name $Version", '') + $subjects | Set-Content $changelog -Encoding utf8
    Write-Host "Drafted changelog.txt from $($subjects.Count) commit(s). Edit it into player-friendly notes, then run without -DraftChangelog."
    return
}

$paks = @(Get-ChildItem $PakDir -Filter "$Prefix*.pak" -File)
if ($paks.Count -eq 0) { throw "No $Prefix*.pak files in $PakDir. Build the mod first." }
$tooBig = $paks | Where-Object Length -gt 2GB
if ($tooBig) { throw "GitHub rejects files over 2 GiB: $($tooBig.Name -join ', '). Split that pak in the build." }

# Freshness: something must have changed since the last release, and the paks must be built after the latest commit.
$problems = @()
if ($lastBuiltFrom -and $head -eq $lastBuiltFrom) { $problems += "No new $Name commits since the last release ($($head.Substring(0,7)))." }
$headTime = [DateTimeOffset]::FromUnixTimeSeconds([long](Invoke-Native { git -C $Source log -1 --format=%ct })).LocalDateTime
$oldestPak = ($paks | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
if ($oldestPak -lt $headTime) { $problems += "Paks were built $oldestPak, before the latest $Name commit ($headTime). Rebuild first." }
if (Invoke-Native { git -C $Source status --porcelain --untracked-files=no }) { Write-Warning "$Name has uncommitted changes; built-from.txt will record $($head.Substring(0,7)) only." }

$notes = Get-Content $changelog -Raw -ErrorAction SilentlyContinue
if (-not $notes -or $notes -match 'WRITE WHAT CHANGED') { $problems += "Write this version's changes in changelog.txt first (or run with -DraftChangelog)." }

# Steam's manifest sits four folders up: Modding\<this repo> -> War of Rights -> common -> steamapps
$manifest = Join-Path $PSScriptRoot '..\..\..\..\appmanifest_424030.acf'
$build = [regex]::Match((Get-Content $manifest -Raw), '"buildid"\s+"(\d+)"').Groups[1].Value
if (-not $build) { throw "Couldn't read the game build from $manifest." }
$gamebuild = Join-Path ([IO.Path]::GetTempPath()) 'gamebuild.txt'
Set-Content $gamebuild $build -NoNewline -Encoding ascii

$totalGB = [math]::Round(($paks | Measure-Object Length -Sum).Sum / 1GB, 2)
Write-Host "$Name $Tag  |  $($paks.Count) paks, $totalGB GB  |  game build $build  |  built from $($head.Substring(0,7))  |  $(if ($Prerelease) {'PRE-RELEASE'} else {'public'})"
$paks | ForEach-Object { Write-Host "  $($_.Name)" }
foreach ($p in $problems) { Write-Warning $p }
if ($DryRun) { Write-Host 'Dry run: nothing uploaded.'; return }
if ($problems -and -not $Force) { throw "Fix the warnings above, or re-run with -Force if you're sure." }

Invoke-Native { gh release view $Tag --repo $Repo *> $null }
if ($LASTEXITCODE -eq 0) { throw "$Tag already exists on $Repo. Pick a new version number." }

# Keep each version's changelog and source commit in the repo history, then publish the release on that commit.
Set-Content $builtFromFile $head -Encoding ascii
Invoke-Native {
    git -C $PSScriptRoot add changelog.txt built-from.txt
    git -C $PSScriptRoot commit -q -m "Release $Tag (built from $Name $($head.Substring(0,7)))" --allow-empty
    git -C $PSScriptRoot push -q
}
if ($LASTEXITCODE -ne 0) { throw "git push failed; nothing was released." }

$assets = @($paks.FullName) + $changelog + $gamebuild
$flags = @('--title', "$Name $Version", '--notes-file', $changelog)
if ($Prerelease) { $flags += '--prerelease' }
Invoke-Native { gh release create $Tag @assets --repo $Repo @flags }
if ($LASTEXITCODE -ne 0) { throw "Upload failed. Delete the half-made release on GitHub ($Tag) and run this again." }
Write-Host "Published $Name $Tag. Players see the update next time they open or refresh the manager."
