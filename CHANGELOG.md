# Changelog

All notable changes to ShieldFrames are documented here.

## Discontinued — 2026-07-27

Development stopped. Removed from WowUp / WowUp Hub distribution. No further releases.

## [1.0.158] — 2026-07-27

### Fixed
- Critical: `ApplyOwnedOvershieldVisual` called `SnapshotBlizzAbsorbWidth` before that local was defined (Lua nil) — every combat update aborted with `attempt to call a nil value` at Core.lua:2248 (`update skip reason: error`). Moved the helper above ApplyOwned so Blood Shield overlays can draw again.

## [1.0.157] — 2026-07-27

### Fixed
- Blood DK damaged/in-bar Blood Shield under Midnight secrets: bootstrap owned hatch from combat evidence without requiring `overAbsorbGlow` (was applying nothing when absorb sat inside missing health)
- Stop clearing player overlay when absorb is secret/`nil` or aura scan briefly misses — require an explicit readable zero plus no hatch/glow/recent absorb evidence
- Restore LastAbsorb seeding before ApplyOwned (regressed in 1.0.155) so secret-aura sizing still works
- Combat leave: keep overlay if Blizzard hatch width cache or recent absorb event still shows a shield

## [1.0.156] — 2026-07-26

### Fixed
- Blood Shield real-time shrink under Midnight secrets: stop `Hide()`ing Blizzard's absorb hatch — alpha-fade only so FillBar/`GetWidth` keep updating while SF draws the owned overlay (was freezing on stale LastAbsorbAmount once the bar was hidden)
