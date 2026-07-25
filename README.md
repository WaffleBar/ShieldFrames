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

#### GitHub topics

Under the repo **About → Topics**, add `unit-frames`. Optional: `warcraft-addon` or `world-of-warcraft-addon`.

## Usage

- **Settings:** Esc → Options → AddOns → **ShieldFrames**, or type `/shieldframes` or `/sf`
- Cast shields (e.g. Power Word: Shield) on party or raid members and watch the overlay on compact frames

## License

MIT — see [LICENSE](LICENSE) if present, or use at your discretion.
