# ShieldFrames

**Overshield overlay for Blizzard's default unit frames** — player, target, focus, pet, and compact party/raid frames.

Blizzard's default overshield indicator is a thin glow line on the right edge of the health bar. ShieldFrames replaces that with a **semi-transparent overlay** that extends **leftward** across the bar in proportion to the **actual overshield amount** — absorb beyond missing health. The overlay is capped so it never extends beyond the health bar frame.

Works with default **player, target, focus, pet**, and **CompactPartyFrame** / **CompactRaidFrame** frames. No custom unit frames, no frame replacements.

## Features

- Overshield overlay width matches real absorb beyond missing health
- Optional left-edge glow with adjustable opacity and color
- Lightweight — hooks Blizzard's existing compact frame elements
- Settings under Esc → Options → AddOns → **ShieldFrames** (`/shieldframes`, `/sf`)

## Requirements

- **Interface → Raid Frames → Display Incoming Heals** must be enabled. ShieldFrames hooks `CompactUnitFrame_UpdateHealPrediction`, which Blizzard only updates when incoming heals are displayed.

## Installation

### Manual

1. Download or clone this repository.
2. Copy the `ShieldFrames` folder into:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Restart WoW (or `/reload` for Lua-only updates; restart for new/changed textures).

### WoWUp

ShieldFrames can be installed from GitHub:

1. In WoWUp, click **Get Addons → Install from URL**
2. Paste: `https://github.com/WaffleBar/ShieldFrames`
3. WoWUp installs from the latest tagged release

For **WowUp Hub** listing, the repo must be **public** with tagged releases that include a packaged zip (created automatically by GitHub Actions when you push a `v*` tag).

#### Preview images

WowUp Hub shows a **Previews** gallery from the `.previews/` folder at release time. The gallery includes in-game style screenshots of party frames, raid frames, overshield close-ups, and the settings panel.

The **addon list thumbnail** uses `Media/AddonIcon.png` via `## IconTexture` in the TOC. The **GitHub / WowUp Hub card banner** uses the repo **Social preview** (`Media/SocialPreview.png`, 1280×640) uploaded under GitHub **Settings → Social preview**.

#### WowUp icon (Install from URL)

If you install with **Get Addons → Install from URL**, WowUp shows the **GitHub account avatar** for `WaffleBar` (the waffle logo), not the addon's `IconTexture`. That is how WowUp's GitHub provider works today — it does not read `Media/AddonIcon.png` for the thumbnail.

What you can do:

1. **In WoW** — Esc → AddOns → ShieldFrames should show the shield/health-bar icon when `Media/AddonIcon.png` is installed (included in release zips).
2. **WowUp Hub search** — Search for **ShieldFrames** under the WowUpHub provider instead of Install from URL. Hub listings use the repo **Social preview** image when one is set.
3. **Set the Social preview** — On GitHub: **ShieldFrames → Settings → Social preview → Upload an image**. Use `.github/social-preview.png` from this repo (1280×640).
4. **Update WowUp** — Remove the old install, then reinstall or update to the latest release (e.g. v1.0.20+) so the zip includes `Media/AddonIcon.png`.

Custom per-addon icons in WowUp for GitHub URL installs are listed as **coming soon** on the [WowUp Hub guide](https://wowup.io/guide/wowup/hub).

#### GitHub topics

Under the repo **About → Topics**, add `unit-frames`. Optional: `warcraft-addon` or `world-of-warcraft-addon`.

## Usage

- **Settings:** Esc → Options → AddOns → **ShieldFrames**, or type `/shieldframes` or `/sf`
- Cast shields (e.g. Power Word: Shield) on party or raid members and watch the overlay on compact frames

## License

MIT — see [LICENSE](LICENSE) if present, or use at your discretion.
