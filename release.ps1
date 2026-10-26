# Publishes a new MAW version for the WoR Mod Manager. See README.md.
#   .\release.ps1 1.3.4 -DraftChangelog   fill changelog.txt from the MAW commits since the last release, then edit it
#   .\release.ps1 1.3.4 -DryRun           check paks, size, game build and freshness without uploading
#   .\release.ps1 1.3.4                   publish
#   -Prerelease  publish a test release players don't get     -Force  skip the "nothing new / stale build" checks
#   -Full        upload every pak, not just the changed ones, so managers older than 1.0.4 get this version too
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$DraftChangelog,
    [switch]$DryRun,
    [switch]$Prerelease,
    [switch]$Force,
    [switch]$Full
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

# Freshness: something must have changed since the last release, and some pak must be built after the latest commit
# (the build rewrites only paks whose contents changed, so the others keep their old dates).
$problems = @()
if ($lastBuiltFrom -and $head -eq $lastBuiltFrom) { $problems += "No new $Name commits since the last release ($($head.Substring(0,7)))." }
$headTime = [DateTimeOffset]::FromUnixTimeSeconds([long](Invoke-Native { git -C $Source log -1 --format=%ct })).LocalDateTime
$newestPak = ($paks | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime
if ($newestPak -lt $headTime) { $problems += "No pak was built after the latest $Name commit ($headTime); newest is $newestPak. Rebuild first." }
if (Invoke-Native { git -C $Source status --porcelain --untracked-files=no }) { Write-Warning "$Name has uncommitted changes; built-from.txt will record $($head.Substring(0,7)) only." }

$notes = Get-Content $changelog -Raw -ErrorAction SilentlyContinue
if (-not $notes -or $notes -match 'WRITE WHAT CHANGED') { $problems += "Write this version's changes in changelog.txt first (or run with -DraftChangelog)." }

# Steam's manifest sits four folders up: Modding\<this repo> -> War of Rights -> common -> steamapps
$manifest = Join-Path $PSScriptRoot '..\..\..\..\appmanifest_424030.acf'
$build = [regex]::Match((Get-Content $manifest -Raw), '"buildid"\s+"(\d+)"').Groups[1].Value
if (-not $build) { throw "Couldn't read the game build from $manifest." }
$gamebuild = Join-Path ([IO.Path]::GetTempPath()) 'gamebuild.txt'
Set-Content $gamebuild $build -NoNewline -Encoding ascii

# Only paks whose bytes changed are uploaded; manifest.txt points every other pak at the release that already holds it.
# The previous state is manifest.txt, or the latest release (which holds every pak) before the first manifest.
$manifestFile = Join-Path $PSScriptRoot 'manifest.txt'
$prev = @{}
if (Test-Path $manifestFile) {
    foreach ($line in Get-Content $manifestFile) {
        $f = -split $line
        if ($f.Count -eq 4) { $prev[$f[0]] = @{ Sha = $f[2]; Tag = $f[3] } }
    }
} else {
    $latest = Invoke-Native { gh release view --repo $Repo --json tagName,assets } | Out-String
    if ($LASTEXITCODE -eq 0) {
        $rel = $latest | ConvertFrom-Json
        foreach ($a in $rel.assets) { if ($a.digest -like 'sha256:*') { $prev[$a.name] = @{ Sha = $a.digest.Substring(7); Tag = $rel.tagName } } }
    }
}
$isFull = $Full -or $prev.Count -eq 0
Write-Host "Hashing $($paks.Count) paks..."
$entries = foreach ($p in $paks | Sort-Object Name) {
    $sha = (Get-FileHash $p.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $old = $prev[$p.Name]
    $changed = $isFull -or -not $old -or $old.Sha -ne $sha
    [pscustomobject]@{ Pak = $p; Sha = $sha; Tag = $(if ($changed) { $Tag } else { $old.Tag }); Changed = $changed }
}
$upload = @($entries | Where-Object Changed)
$dropped = @($prev.Keys | Where-Object { $_ -like "$Prefix*.pak" -and -not ($paks.Name -contains $_) } | Sort-Object)
if ($dropped) { $problems += "These paks aren't in the build and would be deleted from players' games: $($dropped -join ', '). Build the full set, or -Force if you meant to drop them." }

$totalGB = [math]::Round(($paks | Measure-Object Length -Sum).Sum / 1GB, 2)
$uploadMB = [math]::Round(($upload.Pak | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "$Name $Tag  |  $($paks.Count) paks, $totalGB GB  |  uploading $($upload.Count) ($uploadMB MB)$(if ($isFull) {', full release'})  |  game build $build  |  built from $($head.Substring(0,7))  |  $(if ($Prerelease) {'PRE-RELEASE'} else {'public'})"
$entries | ForEach-Object { Write-Host "  $(if ($_.Changed) {'upload'} else {"keep $($_.Tag)"})`t$($_.Pak.Name)" }
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

$assets = @($upload.Pak.FullName) + $changelog + $gamebuild
$flags = @('--title', "$Name $Version", '--notes-file', $changelog)
if ($Prerelease) { $flags += '--prerelease' }
# Managers before 1.0.4 read only the latest release and would delete the paks a partial one leaves out.
if (-not $isFull) { $flags += '--latest=false' }
Invoke-Native { gh release create $Tag @assets --repo $Repo @flags }
if ($LASTEXITCODE -ne 0) { throw "Upload failed. Delete the half-made release on GitHub ($Tag) and run this again." }
if ($Prerelease) { Write-Host "Published test release $Tag. Players don't get it."; return }

# Pushed only after the upload, so players never see a manifest pointing at files that aren't there yet.
$lines = @("version $Tag") + ($entries | ForEach-Object { "$($_.Pak.Name) $($_.Pak.Length) $($_.Sha) $($_.Tag)" })
foreach ($f in $changelog, $gamebuild) { $lines += "$(Split-Path $f -Leaf) $((Get-Item $f).Length) $((Get-FileHash $f -Algorithm SHA256).Hash.ToLowerInvariant()) $Tag" }
[IO.File]::WriteAllLines($manifestFile, $lines)   # no BOM: the manager reads the first line
Invoke-Native {
    git -C $PSScriptRoot add manifest.txt
    git -C $PSScriptRoot commit -q -m "Manifest for $Tag"
    git -C $PSScriptRoot push -q
}
if ($LASTEXITCODE -ne 0) { throw "Released $Tag, but pushing manifest.txt failed. Players won't see it until you push: git -C `"$PSScriptRoot`" push" }
Write-Host "Published $Name $Tag. Players see the update next time they open or refresh the manager (GitHub can take ~5 minutes)."
