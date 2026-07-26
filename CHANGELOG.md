# Changelog

All notable changes to ShieldFrames are documented here.

## [1.0.85] — 2026-07-26

### Fixed
- Glow pins to the stripe’s left edge instead of a reversed width anchor that jumped left when combat ended
- When fill width is readable, stripe anchors to the reverse-fill again so the post-combat health/stripe gap closes

## [1.0.84] — 2026-07-26

### Fixed
- Combat stripe/glow sizing uses readable absorb (or last known amount) and owned bar width instead of secret `SetValue` / `GetWidth`
- Stripe texcoords track absorb/max continuously so the texture keeps up while Blood Shield changes
- Leaving combat no longer hard-clears the overlay while Blood Shield is still active (avoids the post-combat jump)

## [1.0.83] — 2026-07-26

### Fixed
- Custom overshield glow shows again when fill width is secret (combat Blood Shield path)
- Glow is only suppressed when width is known to be under 8px, not when width is unavailable

## [1.0.82] — 2026-07-26

### Fixed
- Leaving combat force-clears custom overlays so secret absorb cannot leave a tiny stripe/glow stuck on the bar tip
- Out of combat, status-bar rendering requires readable absorb+max; secret bar/bootstrap paths are combat-only (unless Blizzard glow is still live)
- Glow is hidden when the overlay fill is under 8px wide to avoid the stray edge line

## [1.0.81] — 2026-07-26

### Fixed
- In-combat Blood Shield no longer clears when aura scans fail under Midnight secret values
- Combat secret absorb only persists with a known aura, last readable absorb, or recent `UNIT_ABSORB_AMOUNT_CHANGED` (Death Strike)
- Known-absorb aura cache is retained across failed combat aura lookups
- Safer aura lookups via `pcall` / `GetAuraDataBySpellID`; Anti-Magic Shell added to known absorb list
- Leaving combat refreshes frames and clears stale absorb-event state

## [1.0.80] — 2026-07-26

### Changed
- Debug tip no longer assumes mage barriers; mentions Blood Shield and other combat absorbs

## [1.0.79] — 2026-07-26

### Fixed
- Combat no longer clears an active shield overlay solely because calculator values are secret
- Cached known-absorb aura state persists across combat when live aura scans fail
- Secret max health from the heal calculator is kept for status-bar sizing in combat
- Status bar accepts secret max and/or secret absorb (`status-bar-secret*` paths)

## [1.0.78] — 2026-07-26

### Fixed
- Debug apply path/bootstrap mode reset when the overlay is cleared

## [1.0.77] — 2026-07-26

### Fixed
- Overlay no longer persists after shield expires when only secret calculator values and a stale custom overlay remain
- Secret absorb now uses the dynamic status bar when max health is readable (`status-bar-secret` path)
- Bootstrap fill anchor only runs when health is below max; full-HP zero-width fill fallback removed
- Removed fixed 48px bootstrap fallback that kept a static stripe after Blizzard glow faded

## [1.0.76] — 2026-07-26

### Fixed
- `UnitHealthMax` is now used for sizing even when current health is secret/unreadable
- Status-bar path requires a readable max health; otherwise falls back to bootstrap fill/width overlay
- Debug reports effective max health, apply path, and clarifies stripe texture on the status bar

## [1.0.75] — 2026-07-26

### Fixed
- Bootstrap no longer treats faded Blizzard glow (`IsShown` at alpha 0) as full-HP width mode; fill anchor tracks health after the glow is hidden
- Full-HP overshield still uses fixed-width stripe only while unfaded Blizzard glow is active
- Overlay stripe draw layer raised so it renders above the health bar fill

## [1.0.74] — 2026-07-26

### Fixed
- Full-HP overshield no longer uses a zero-width fill anchor; Blizzard glow now triggers the fixed-width stripe bootstrap first
- Damaged-health overshields still use fill-anchored stripes that track the health bar

## [1.0.73] — 2026-07-26

### Fixed
- Secret calculator absorb no longer counts as active without a live aura, glow, or existing overlay; shields clear when readable absorb is explicitly zero
- Bootstrap overlay re-anchors to the health fill every update so the stripe tracks health instead of freezing
- Removed max-health-unavailable early exit that left stale overlays visible while skipping re-apply
- Full-HP overshield uses fixed-width bootstrap only while Blizzard overshield glow is active

## [1.0.72] — 2026-07-26

### Fixed
- Eliminated all `healthBar:GetWidth()` reads on Blizzard unit frames, which taint heal prediction even outside hooks
- Pet frame is no longer updated for midnight overshields; stale pet overlays are cleared instead
- Bootstrap overlay width uses a safe default/cached value rather than querying bar geometry

## [1.0.71] — 2026-07-26

### Fixed
- Unit frame hook updates are deferred to the next frame so health bar width reads no longer taint Blizzard heal prediction secret values
- Health values prefer `UnitHealth`/`UnitHealthMax` over status bar reads; bar width is cached and wrapped in safe pcalls

## [1.0.70] — 2026-07-26

### Fixed
- Overlay no longer persists after the shield is gone; absorb detection no longer treats stale flags, faded glow, or secret calculator placeholders as active absorb
- Bootstrap stripe overlay now anchors to the live health fill when health is below max, so it moves as health changes instead of staying at a fixed pixel width
- Secret absorb values only count as active while the calculator has not reported an explicit zero

## [1.0.69] — 2026-07-26

### Fixed
- Midnight absorb detection now treats secret calculator values, faded Blizzard glow, and active custom overlays as valid absorb signals
- Overlay no longer disappears on the next tick after the Blizzard overshield glow is hidden by ShieldFrames

## [1.0.68] — 2026-07-26

### Fixed
- Bootstrap stripe overlay no longer crashes with "attempt to call a nil value" at apply time; `ApplyOverlayAndGlow` is defined before bootstrap callers (Lua forward-reference fix)

## [1.0.67] — 2026-07-26

### Fixed
- Midnight combat updates now detect secret absorb values and Blizzard overshield glow reliably instead of exiting before apply
- Secret absorb coalescing no longer uses `or`, which could drop secret calculator values
- Update lock skips, inner pcall failures, and early-exit reasons are recorded and shown in `/sfdebug`
- Unsafe `IsForbidden()` calls in blizzard overlay suppression and hide paths

## [1.0.66] — 2026-07-26

### Fixed
- `/sfdebug` no longer crashes with "attempt to call a nil value" when checking midnight absorb state
- `FrameShowsAbsorbBar` is defined before callers that reference it, fixing a Lua forward-reference bug in combat

## [1.0.65] — 2026-07-26

### Fixed
- Midnight player frame updates no longer bail out when the Blizzard health bar is forbidden in combat
- Bootstrap stripe overlay textures parent to the unit frame when the health bar cannot accept child frames
- `/sfdebug` reports health bar forbidden state, absorb detection signals, and last apply result

## [1.0.64] — 2026-07-25

### Fixed
- Player frame updates no longer silently abort when `healthBar:IsForbidden` is missing (Lua method call error)
- Safe forbidden checks on custom overlay textures used by debug and overlay visibility detection

## [1.0.63] — 2026-07-25

### Fixed
- Bootstrap stripe overlay no longer fails in combat when health bar width/height is secret or zero; falls back to a fixed pixel width while Blizzard overshield glow is active
- Health bar width reads are wrapped in safe accessors for midnight secret dimensions

## [1.0.62] — 2026-07-25

### Fixed
- Secret midnight absorb values now use a geometry-based stripe overlay when the reverse-fill status bar cannot accept secret SetValue
- Update lock is always released even if midnight rendering errors, preventing stuck frame updates
- `/sfdebug` refreshes the player frame first and reports both status-bar and texture overlay state

## [1.0.61] — 2026-07-25

### Fixed
- Midnight combat rendering now passes secret calculator absorb values directly to the overlay status bar instead of discarding them
- Stripe overlay anchors to the rendered fill even when fill width is secret/unreadable
- Debug output distinguishes secret values that are still being rendered from unavailable values

## [1.0.60] — 2026-07-25

### Fixed
- Custom overlay renders when Blizzard's `overAbsorbGlow` is active but midnight absorb amounts are secret
- Secret calculator/readable absorb values fall back to bar width, missing-health, or last-known estimates instead of aborting
- `/sfdebug` no longer misreports "no player frame" when readable overshield is simply false

## [1.0.59] — 2026-07-25

### Fixed
- `/sfdebug` and absorb aura parsing no longer crash when Midnight marks aura table fields as secret
- Aura spell ID and absorb point reads are wrapped in safe accessors compatible with secret values

## [1.0.58] — 2026-07-25

### Fixed
- Blood Shield and other known absorb auras render again when aura absorb amounts are secret, while still clearing once aura points read zero
- Hide logic no longer treats "buff present + unreadable absorb" as "no absorb"
- Last-known absorb amount is reused only while a non-depleted known absorb aura remains active

## [1.0.57] — 2026-07-25

### Fixed
- Overshield overlay no longer persists after absorb fades when a known absorb aura buff is still present but its remaining amount reads zero
- Absorb aura detection now requires live absorb (readable points, total absorbs, or Blizzard absorb bar) instead of buff presence alone
- Stale bar-width estimates are ignored once Blizzard's absorb bar is hidden

## [1.0.56] — 2026-07-25

### Fixed
- Blood Shield and other non-mage absorb auras (Power Word: Shield, Shield of Vengeance, etc.) are detected for midnight overlay rendering
- Overshield stripe overlay no longer gets clipped away when it extends left into missing-health space
- Stripe and glow render from computed absorb width when status bar fill width is secret/unreadable

## [1.0.55] — 2026-07-25

### Fixed
- Overshield overlay no longer persists after absorb fades; removed sticky self-referential detection and stale last-known absorb fallback
- Clear no-absorb signals (zero readable absorb, no barrier aura, no Blizzard absorb bar/glow) now force-hide the custom overlay

## [1.0.54] — 2026-07-25

### Fixed
- `/sfdebug` no longer hangs or fails silently: removed frame refresh from debug, added nil-safe player frame checks, and prints an immediate ack line
- Blazing Barrier and other mage barriers detected via aura when `UnitGetTotalAbsorbs` reads zero under Midnight secret values
- Absorb fallback chain no longer stops early on readable zero; Blizzard absorb bar width is sampled before suppression
- Re-entrant midnight frame updates are guarded to prevent hook recursion

## [1.0.53] — 2026-07-25

### Fixed
- Midnight absorb detection now treats any active absorb as display-worthy, not only the overshield segment beyond missing health
- Falls back to Blizzard's absorb bar width and last known amount when API values are secret

## [1.0.52] — 2026-07-25

### Fixed
- Full-health absorbs like Blazing Barrier render again when the calculator reports zero overshield segment but positive total absorb
- Midnight overlay no longer aborts when calculator max health is unavailable; falls back to unit frame health values

## [1.0.51] — 2026-07-25

### Fixed
- Blazing Barrier and other full-health absorbs show the overshield overlay again; detection no longer relies on Blizzard glow fallback

## [1.0.50] — 2026-07-25

### Fixed
- Edge glow no longer persists at full health after overshield fades; releasing Blizzard glow suppression now hides the texture instead of restoring it visible

## [1.0.49] — 2026-07-25

### Fixed
- Lua forward-reference crash in `MidnightFrameHasOvershield` (`/sfdebug` and overshield updates)

## [1.0.48] — 2026-07-25

### Fixed
- Settings sliders and glow color now use the same proxy save path as other Waffle addons, with live frame refresh
- Opacity values stored as decimals (0.50) are migrated correctly instead of rendering near-invisible
- Blizzard's default absorb bar is hidden while the ShieldFrames overlay is active so custom color/opacity is visible

## [1.0.47] — 2026-07-25

### Fixed
- Overlay Opacity and Glow Opacity sliders now save correctly and refresh the live shield display
- Shield stripe texture alpha follows Overlay Opacity instead of using a fixed value

## [1.0.46] — 2026-07-25

### Fixed
- Overshield overlay no longer flashes during shields like Blazing Barrier when absorb values alternate between readable and secret

## [1.0.45] — 2026-07-25

### Fixed
- Edge glow no longer lingers at full health when there is no overshield; removed sticky overshield state and added readable health/absorb fallback

## [1.0.44] — 2026-07-25

### Changed
- Author metadata updated to **Waffle**

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
