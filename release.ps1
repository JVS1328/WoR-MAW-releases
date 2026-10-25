# Publishes a new MAW version for the WoR Mod Manager. See README.md.
# Usage:  .\release.ps1 1.3.4            (add -DryRun to only show what would be uploaded,
#                                          -Prerelease to publish a test release players don't get)
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$DryRun,
    [switch]$Prerelease
)
$ErrorActionPreference = 'Stop'

$Name   = 'MAW'
$Repo   = 'JVS1328/WoR-MAW-releases'
$PakDir = Join-Path $PSScriptRoot '..\WoR-MAW\out'
$Prefix = 'z_maw_'

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.3.4 (got '$Version')." }
$Tag = "v$Version"

$paks = @(Get-ChildItem $PakDir -Filter "$Prefix*.pak" -File)
if ($paks.Count -eq 0) { throw "No $Prefix*.pak files in $PakDir. Build the mod first." }
$tooBig = $paks | Where-Object Length -gt 2GB
if ($tooBig) { throw "GitHub rejects files over 2 GiB: $($tooBig.Name -join ', '). Split that pak in the build." }

$changelog = Join-Path $PSScriptRoot 'changelog.txt'
$notes = (Get-Content $changelog -Raw -ErrorAction SilentlyContinue)
if (-not $notes -or $notes -match 'WRITE WHAT CHANGED') {
    if ($DryRun) { Write-Warning "changelog.txt still needs this version's changes." }
    else { throw "Write this version's changes in changelog.txt first." }
}

# Steam's manifest sits four folders up: Modding\<this repo> -> War of Rights -> common -> steamapps
$manifest = Join-Path $PSScriptRoot '..\..\..\..\appmanifest_424030.acf'
$build = [regex]::Match((Get-Content $manifest -Raw), '"buildid"\s+"(\d+)"').Groups[1].Value
if (-not $build) { throw "Couldn't read the game build from $manifest." }
$gamebuild = Join-Path ([IO.Path]::GetTempPath()) 'gamebuild.txt'
Set-Content $gamebuild $build -NoNewline -Encoding ascii

$totalGB = [math]::Round(($paks | Measure-Object Length -Sum).Sum / 1GB, 2)
Write-Host "$Name $Tag  |  $($paks.Count) paks, $totalGB GB  |  game build $build  |  $(if ($Prerelease) {'PRE-RELEASE'} else {'public'})"
$paks | ForEach-Object { Write-Host "  $($_.Name)" }
if ($DryRun) { Write-Host 'Dry run: nothing uploaded.'; return }

# Native-command stderr would trip 'Stop' in Windows PowerShell, so check exit codes instead.
$ErrorActionPreference = 'Continue'
gh release view $Tag --repo $Repo *> $null
if ($LASTEXITCODE -eq 0) { throw "$Tag already exists on $Repo. Pick a new version number." }

# Keep each version's changelog in the repo history, then publish the release on that commit.
git -C $PSScriptRoot add changelog.txt
git -C $PSScriptRoot commit -q -m "Release $Tag" --allow-empty
git -C $PSScriptRoot push -q
if ($LASTEXITCODE -ne 0) { throw "git push failed; nothing was released." }

$assets = @($paks.FullName) + $changelog + $gamebuild
$flags = @('--title', "$Name $Version", '--notes-file', $changelog)
if ($Prerelease) { $flags += '--prerelease' }
gh release create $Tag @assets --repo $Repo @flags
if ($LASTEXITCODE -ne 0) { throw "Upload failed. Delete the half-made release on GitHub ($Tag) and run this again." }
Write-Host "Published $Name $Tag. Players see the update next time they open or refresh the manager."
