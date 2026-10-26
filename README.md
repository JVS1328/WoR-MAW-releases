# WoR-MAW-releases

Public release files for **War of Rights: Mexican-American War (MAW)**, read by the
[WoR Mod Manager](https://github.com/JVS1328/WoR-ModManager-releases). The mod's source lives in the private
`WoR-MAW` repo; this repo only holds what players download.

## What the manager reads

| File | Where | What it's for |
|---|---|---|
| `thumbnail.png` (or `.jpg`) | this repo | Picture on the mod's card. 16:9, about 960x540. |
| `description.txt` | this repo | Card text. **If the first line is a nexusmods.com link**, it becomes the "View on Nexus" button and the rest is the text. |
| `manifest.txt` | this repo | The current version: every `z_maw_*.pak` with its checksum and the release that holds it. Written by `release.ps1`; don't edit it. |
| Releases | Releases tab | Tag = version (`v1.3.4`). Each holds the paks that changed in that version + `changelog.txt` + `gamebuild.txt`. |

Editing `thumbnail.jpg` or `description.txt` on github.com updates every player's card the next time
they open or refresh the manager (GitHub can take ~5 minutes).

## Releasing a new version

1. Make your changes in `..\WoR-MAW`, **commit them**, and build, so `..\WoR-MAW\out\z_maw_*.pak` is the new full set.
2. Draft the changelog from your commits since the last release, then edit it into player-friendly notes
   (it's shown to players before they update):

   ```powershell
   .\release.ps1 1.3.4 -DraftChangelog
   ```

3. Check, then publish:

   ```powershell
   .\release.ps1 1.3.4 -DryRun     # pak list, size, game build, and warnings
   .\release.ps1 1.3.4             # publish
   ```

   The script stops if no pak and no game build changed since the last release, if no pak was built after
   your latest commit (forgot to rebuild), if a pak from the last version is missing from the build, or if
   `changelog.txt` wasn't written. `-Force` overrides all but the last. A game-patch rebuild with no new
   commit is fine: its paks or game build changed.
   On publish it writes the game's Steam build into `gamebuild.txt`, records the source commit in
   `built-from.txt`, commits both with `changelog.txt`, creates release `v1.3.4`, uploads **only the paks whose
   bytes changed**, then pushes `manifest.txt`. A one-file patch uploads in seconds.
4. Done. Players get "Update available" and download **only the paks that changed**. Paks you
   dropped from the build are removed from their game.

**Rules**
- Build the full set of paks every time. A pak missing from the build is dropped from `manifest.txt` and deleted
  from players' games.
- **Never delete an old release.** `manifest.txt` still points at the paks it holds.
- Managers older than 1.0.4 only see releases made with `-Full` (every pak uploaded). Use it now and then,
  e.g. after a game patch, so players who haven't updated the manager still get the mod.
- Each file must be under 2 GiB (GitHub's limit). The script stops if one isn't.
- Version numbers only go up (`1.3.4` → `1.3.5`). The script refuses a version that already exists.
- To test a build without players getting it, add `-Prerelease`. The manager ignores pre-releases.
  Delete it on GitHub afterwards, or edit it and untick "pre-release" to make it the real one.
- If an upload fails halfway, delete the half-made release on the Releases page and run the script again.

## First-time setup on a new PC

Install the [GitHub CLI](https://cli.github.com/) and run `gh auth login` once.
