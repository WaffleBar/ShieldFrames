# Changelog

All notable changes to ShieldFrames are documented here.

## [1.0.43] — 2026-07-25

### Fixed
- Overshield overlay now tints with your chosen glow color instead of rendering as a dark default stripe texture
- Suppresses Blizzard's native absorb overlay on player/target frames so it doesn't stack underneath
- Edge glow renders above the fill with correct draw layering

## [1.0.42] — 2026-07-25

### Fixed
- Glow color picker Cancel no longer errors; handles modern `GetPreviousValues()` return format

## [1.0.41] — 2026-07-25

### Fixed
- Settings error after closing the glow color picker (`cbrHandles` missing on About row)

## [1.0.40] — 2026-07-25

### Fixed
- Glow color picker now opens as a centered modal instead of overlapping the settings list

## [1.0.39] — 2026-07-25

### Changed
- Glow color picker aligned to the center control column with checkboxes and sliders

## [1.0.38] — 2026-07-25

### Fixed
- Glow color swatch no longer uses ColorSwatchTemplate white chrome; inset rounded color panel matches preview
- Dropdown chevron rotation corrected to point down

## [1.0.37] — 2026-07-25

### Changed
- Glow color picker matches preview layout: inset rounded ColorSwatch on the left and a plain gray chevron on the right (no edge-to-edge fill or square arrow button)

## [1.0.36] — 2026-07-25

### Fixed
- Glow color picker chevron now uses the retail dropdown arrow texture instead of a missing-font box character

## [1.0.35] — 2026-07-25

### Fixed
- Glow color picker matches preview structure: dark rounded outer frame, inset color swatch, flat arrow panel, and gray chevron (no nested dropdown button)

## [1.0.34] — 2026-07-25

### Fixed
- Glow color picker is now one unified control (color panel + divider + arrow panel) instead of a separate swatch and dropdown button with a gap

## [1.0.33] — 2026-07-25

### Changed
- Glow color picker now uses Blizzard's WowStyle1DropdownTemplate for the same dropdown chrome as retail settings (color panel + divider + chevron)

## [1.0.32] — 2026-07-25

### Changed
- Glow color control now uses a preview-style dropdown color button (wide swatch + chevron) and correctly displays the saved glow color

## [1.0.31] — 2026-07-25

### Fixed
- About blurb and glow color picker now use custom Blizzard settings row templates instead of empty button initializers, fixing the full-width red bars

## [1.0.30] — 2026-07-25

### Fixed
- About description and glow color swatch no longer render as full-width red buttons; settings initializers now attach their custom UI correctly

## [1.0.29] — 2026-07-25

### Changed
- Settings panel reorganized to match published previews: About blurb, single General section, decimal opacity sliders (Low/High), and inline glow color swatch
- Removed separate Overshield Display / Appearance sections and the overlay color picker from settings (overlay tint stays at the default white)

## [1.0.28] — 2026-07-25

### Fixed
- Edge glow visible again on real overshield when absorb values are secret; only suppress glow when overshield amount is known to be zero
- Parent custom glow to the clip frame so it draws above the clipped overlay bar

## [1.0.27] — 2026-07-25

### Fixed
- Color picker Cancel no longer errors; Midnight's `GetPreviousValues()` returns a scalar, so cancel restores the RGB captured when the picker opened

## [1.0.26] — 2026-07-25

### Fixed
- Color picker Cancel no longer triggers an immediate refresh storm; restores glow fade state and defers frame updates
- Compact/unit frame updates wrapped in pcall so midnight secret-value edge cases cannot error during settings changes

## [1.0.25] — 2026-07-25

### Fixed
- Midnight overshield math and comparisons wrapped in safe accessors so tainted calculator values cannot throw on party/raid frames

## [1.0.24] — 2026-07-25

### Fixed
- Secret-value Lua error on party/raid frames when checking Blizzard overshield glow alpha (track fade state instead of comparing `GetAlpha()`)

## [1.0.23] — 2026-07-25

### Fixed
- Edge glow no longer lingers when only in-bar absorb is present; midnight path derives overshield from total minus clamped absorb and ignores Blizzard's faded glow for detection

## [1.0.22] — 2026-07-25

### Fixed
- Overshield overlay no longer leaves a gap at partial HP; the bar is clipped to the current health fill so only the backfill portion is visible

## [1.0.21] — 2026-07-25

### Fixed
- Lua errors on party/raid frames when health bar height is secret (stripe tex coord math no longer divides secret values)

## [1.0.20] — 2026-07-25

### Fixed
- Overlay color picker tints a solid underlay; stripe texture sits on top so health bar blue no longer bleeds through

## [1.0.19] — 2026-07-25

### Fixed
- `/sfdebug` uses `C_AddOns.GetAddOnMetadata` (global removed in Midnight)

## [1.0.18] — 2026-07-25

### Fixed
- Restore visible overshield StatusBar rendering (hidden measure bar had zero-size fill)
- Parent glow to overlay bar so it draws above the health bar
- Debug output reads version from TOC and reports bar/glow state

## [1.0.17] — 2026-07-25

### Fixed
- Overshield overlay and glow render again when absorb width values are secret (anchor to measure bar fill instead of reading width)

## [1.0.16] — 2026-07-25

### Added
- Overlay Color picker in settings to tint the overshield stripe fill

## [1.0.15] — 2026-07-25

### Fixed
- Overshield stripes now use a tiled texture with Blizzard-style tex coords instead of a stretched status bar fill

## [1.0.14] — 2026-07-25

### Fixed
- Glow color picker no longer closes the Settings panel; uses `SetupColorPickerAndShow` like other addons

## [1.0.13] — 2026-07-25

### Fixed
- Overshield glow texture sublevel exceeded WoW's -8..7 limit on status bars

## [1.0.12] — 2026-07-25

### Fixed
- Debug and midnight overshield updates no longer call helpers before they are defined

## [1.0.11] — 2026-07-25

### Fixed
- Use `GetTotalDamageAbsorbs()` for overlay width (in-bar clamped amount is 0 at full HP)
- Stop hiding Blizzard's overshield glow with `:Hide()`; fade it instead so detection keeps working
- Keep overlay active across ticker updates until the absorb actually ends

## [1.0.10] — 2026-07-25

### Fixed
- Do not branch on secret booleans from `GetDamageAbsorbs`; detect overshield via Blizzard's `overAbsorbGlow` instead

## [1.0.9] — 2026-07-25

### Fixed
- Midnight (12.0) secret health/absorb values no longer block overshield detection
- Player, target, and compact frames now use Blizzard's `UnitHealPredictionCalculator` API when available
- Debug output reports overshield state without requiring readable health numbers

## [1.0.8] — 2026-07-25

### Fixed
- `/sfdebug` was accidentally registered on the settings handler, so it opened settings instead of printing debug info
- Debug output no longer silently fails when health or absorb values are secret (common in combat)
- Slash commands register at load time and print through the default chat frame

## [1.0.7] — 2026-07-25

### Fixed
- `/sf debug` no longer falls through to settings; added dedicated `/sfdebug` command

## [1.0.6] — 2026-07-25

### Fixed
- Player/target frames now draw a dedicated ShieldFrames overlay texture on the health bar
- Color picker closes Settings first so Okay/Cancel receive clicks, then reopens settings

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
