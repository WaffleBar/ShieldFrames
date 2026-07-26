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

- `01-player-frame-with-color.png` — player frame with colored overshield overlay
- `02-player-overshield.png` — player frame with cyan overshield stripe and edge glow
- `03-sf-settings.png` — ShieldFrames settings panel

Replace these with your own screenshots anytime; commit and tag a new release so WowUp Hub re-indexes the gallery.

Regenerate the **GitHub / WowUp card thumbnail** (1280×1280 square) with:

```powershell
csc /out:tools/MakeSocialPreview.exe tools/MakeSocialPreview.cs
tools/MakeSocialPreview.exe .
```

Then upload `.github/social-preview.png` under GitHub **Settings → Social preview**.

After adding or changing images, commit to `main` and push a new version tag (e.g. `v1.0.87`) so WowUp Hub re-indexes the gallery.
