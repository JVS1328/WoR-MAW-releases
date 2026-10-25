# WoR-MAW-releases

Public release files for **War of Rights: Mexican-American War (MAW)**, read by the
[WoR Mod Manager](https://github.com/JVS1328/WoR-ModManager). The mod's source lives in the private
`WoR-MAW` repo; this repo only holds what players download.

## What the manager reads

| File | Where | What it's for |
|---|---|---|
| `thumbnail.jpg` (or `.png`) | this repo | Picture on the mod's card. 16:9, about 960x540. |
| `description.txt` | this repo | Card text. **If the first line is a nexusmods.com link**, it becomes the "View on Nexus" button and the rest is the text. |
| Latest release | Releases tab | Tag = version (`v1.3.4`). Assets = **every** `z_maw_*.pak` + `changelog.txt` + `gamebuild.txt`. |

Editing `thumbnail.jpg` or `description.txt` on github.com updates every player's card the next time
they open or refresh the manager (GitHub can take ~5 minutes).

## Releasing a new version

1. Build the mod as usual, so `..\WoR-MAW\out\z_maw_*.pak` is the new full set.
2. Write what changed in `changelog.txt` (replace the whole file; it's shown to players before they update).
3. In this folder, run:

   ```powershell
   .\release.ps1 1.3.4 -DryRun     # check the pak list, size and game build
   .\release.ps1 1.3.4             # publish
   ```

   The script reads the game's Steam build into `gamebuild.txt`, commits `changelog.txt`, creates
   release `v1.3.4` and uploads all the paks (~8.5 GB, so give it time).
4. Done. Players get "Update available" and download **only the paks that changed**. Paks you
   dropped from the build are removed from their game.

**Rules**
- Always upload the full set of paks. A pak missing from the newest release gets deleted from players' games.
- Each file must be under 2 GiB (GitHub's limit). The script stops if one isn't.
- Version numbers only go up (`1.3.4` → `1.3.5`). The script refuses a version that already exists.
- To test a build without players getting it, add `-Prerelease`. The manager ignores pre-releases.
  Delete it on GitHub afterwards, or edit it and untick "pre-release" to make it the real one.
- If an upload fails halfway, delete the half-made release on the Releases page and run the script again.

## First-time setup on a new PC

Install the [GitHub CLI](https://cli.github.com/) and run `gh auth login` once.
