# WowUp Hub preview images

WowUp Hub reads PNG/JPG files from this folder when you publish a **tagged release** from the same branch.

## What shows where

| Location | Source |
|----------|--------|
| **Addon card thumbnail** | GitHub repo **Social preview** (Settings → Social preview) |
| **Previews gallery** | Every image in this `.previews/` folder at release time |
| **In-game / WowUp addon icon** | `Media/AddonIcon.png` via `## IconTexture` in the TOC |

This folder is **not** packaged into the WoW addon zip (see `.pkgmeta`).

## Files

- `01-party-ingame.png` — party frames with overshield in a dungeon
- `02-raid-ingame.png` — raid frames with overshield during an encounter
- `03-overshield-closeup.png` — close-up of the overlay and edge glow
- `04-settings-ingame.png` — ShieldFrames settings panel

Replace these with your own screenshots anytime; commit and tag a new release so WowUp Hub re-indexes the gallery.

Regenerate the **GitHub / WowUp card thumbnail** (1280×1280 square) with:

```powershell
csc /out:tools/MakeSocialPreview.exe tools/MakeSocialPreview.cs
tools/MakeSocialPreview.exe .
```

Then upload `.github/social-preview.png` under GitHub **Settings → Social preview**.

After adding or changing images, commit to `main` and push a new version tag (e.g. `v1.0.0`) so WowUp Hub re-indexes the gallery.
