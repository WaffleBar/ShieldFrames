# Changelog

All notable changes to ShieldFrames are documented here.

## [1.0.5] — 2026-07-25

### Fixed
- Player frame overlay now targets modern `TiledOverlay`/`FillMask` absorb elements
- Health reads fall back to `UnitHealth` when status bar values are secret
- Color picker raises above the Settings panel so Okay/Cancel respond

## [1.0.4] — 2026-07-25

### Fixed
- Settings panel registers on player login so controls actually appear
- Player/target frames use `totalAbsorbBarOverlay` (correct Blizzard element name)
- Player frame overshield overlay follows the proven UnitFrame absorb bar layout

## [1.0.3] — 2026-07-25

### Fixed
- Settings panel now registers correctly (prefixed setting IDs, proper SavedVariables binding)
- Overshield overlay now updates on player, target, focus, and pet frames as well as compact party/raid frames
- Added absorb/health event listeners so overlays refresh without relying solely on heal prediction updates

## [1.0.2] — 2026-07-25

### Added
- Expanded addon description in the in-game addon list, settings panel, and README
- In-game style preview images for the WowUp Hub gallery

### Changed
- Replaced placeholder gallery images with party, raid, close-up, and settings previews

## [1.0.1] — 2026-07-24

### Changed
- **Hub gallery** — added party, settings, and raid frame preview images
- **Social preview** — added 1280×640 repository banner for GitHub and WowUp Hub

## [1.0.0] — 2026-07-24

### Added
- Overshield overlay on Blizzard default party and raid compact frames
- Transparent absorb bar extending left from the health bar edge, sized to real overshield value
- Optional left-edge glow with opacity and color controls
- Settings panel under Esc → Options → AddOns → ShieldFrames (`/shieldframes`, `/sf`)
- Addon icon for WoW and addon managers
