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

- `01-party-overshield.png` — party frames with overshield overlay
- `02-settings-panel.png` — ShieldFrames settings panel
- `03-raid-frames.png` — raid frames with overshield highlights

The repository **social preview** banner lives at `Media/SocialPreview.png` (1280×640) and is mirrored in `.github/social-preview.png` for easy upload to GitHub Settings.

After adding or changing images, commit to `main` and push a new version tag (e.g. `v1.0.0`) so WowUp Hub re-indexes the gallery.
