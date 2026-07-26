# Changelog

All notable changes to ShieldFrames are documented here.

## [1.0.150] — 2026-07-26

### Fixed
- Combat microstutter / high CPU: replace 0.15s full-raid poll with 1s evidence-only safety tick; ignore non-group unit events; coalesce health/heal-pred updates; cache absorb aura scans per unit so secret-value fallbacks do not re-scan 40 auras multiple times per frame

## [1.0.149] — 2026-07-26

### Fixed
- Secret-boolean taint: stop boolean-testing `UnitIsUnit` / `IsShown` / `GetClipsChildren` results on Midnight party frames
- Player cast bar icon clipped: only force `SetClipsChildren` on compact party/raid frames, never Player/Target/Focus

## [1.0.148] — 2026-07-26

### Fixed
- Priest self-shield sticky after expire: stop re-caching SoftHide width as live absorb; clear player frames when aura/absorb reads empty

## [1.0.147] — 2026-07-26

### Fixed
- Glow Opacity slider had no effect: draw path forced alpha ≥ 0.95; now uses the setting value

## [1.0.146] — 2026-07-26

### Fixed
- Divine Aegis (47753) from Radiance/crit heals: track in seed list; keep a full-size leading glow on small hatches (no longer shrink glow with absorb width)

## [1.0.145] — 2026-07-26

### Fixed
- Stacked absorbs (e.g. PW:S + Blazing Barrier): hatch grows to max(Blizzard width, summed tracked auras / estimates); look up absorb auras by spell ID when party aura scans miss them

## [1.0.144] — 2026-07-26

### Fixed
- Inconsistent glow by shield spell: size hatch+glow from Blizzard absorb width for all absorbs; stop clearing that width when we SoftHide Blizzard chrome

## [1.0.143] — 2026-07-26

### Fixed
- ADDON_ACTION_BLOCKED taint: stop learning absorbs inside Blizzard FillBar/heal-prediction hooks and drop CLEU learning; defer learn to `UNIT_AURA` / `UNIT_ABSORB_AMOUNT_CHANGED` via `C_Timer.After(0)`

## [1.0.142] — 2026-07-26

### Changed
- Absorb detection no longer depends on hand-maintained per-spec spell lists: scan helpful auras, auto-learn spell IDs from readable `UnitGetTotalAbsorbs`, and keep a small seed list only as a bootstrap

## [1.0.141] — 2026-07-26

### Fixed
- Priest Void Shield (spell 1253593) was not a known absorb aura — player OOC clear wiped our glow while Blizzard hatch remained; recognize Void Shield and keep FillBar-sized absorbs

## [1.0.140] — 2026-07-26

### Fixed
- Priest missing glow: ADD blend on white health clamps invisible; draw SoftEdgeGlow with BLEND (+ ADD on top for colored bars)

## [1.0.139] — 2026-07-26

### Changed
- Tighten seam glow width and texture falloff

## [1.0.138] — 2026-07-26

### Changed
- Ship `Media/SoftEdgeGlow.tga` (bright center, soft alpha falloff both ways) and use that as the single seam glow

## [1.0.137] — 2026-07-26

### Changed
- Real soft glow: mirrored `Shield-Overshield` wings with ADD blend (bright center at the seam, falloff both ways; no flat strip bar)

## [1.0.135] — 2026-07-26

### Fixed
- Simplify edge glow back to one WHITE8X8 seam marker (cyan-on-white is fine if drawn; prior soft/strip/gradient paths were the real failure)

## [1.0.133] — 2026-07-26

### Fixed
- Glow missing again after gradient attempt: draw soft edge as stacked WHITE8X8 strips (same solid texture that was visibly working)

## [1.0.132] — 2026-07-26

### Fixed
- Harsh black glow bar: `Shield-Overshield` + BLEND showed atlas black pixels; replace with a soft horizontal alpha gradient (works on priest white and mage blue)

## [1.0.131] — 2026-07-26

### Fixed
- Glow missing or “random” bar: stop cross-anchoring to the overlay; place soft+ADD glow from the same leftInset as the hatch (visible on priest and mage)

## [1.0.130] — 2026-07-26

### Fixed
- Priest party frames: edge glow invisible on white health bars (ADD blend); use BLEND and draw above the hatch on the health side only

## [1.0.129] — 2026-07-26

### Fixed
- Hatch+glow stuck after shields expired: stop redrawing from cached Blizzard/last overlay width; clear caches when auras are gone

## [1.0.128] — 2026-07-26

### Fixed
- Flat strip beside the glow: draw glow under the hatch, flip soft falloff toward the edge, and stop overlapping hatch pixels

## [1.0.127] — 2026-07-26

### Changed
- Edge marker uses Blizzard `Shield-Overshield` with ADD blend for a soft glow instead of a flat bar

## [1.0.126] — 2026-07-26

### Fixed
- Lua error `SafeOverlayHeight` nil at apply time (local defined after use) — hatch + glow never drew

## [1.0.125] — 2026-07-26

### Fixed
- Glow missing after 1.0.124: draw a solid WHITE8X8 edge bar on the same clip as the hatch (no cross-frame holder / Shield-Overshield)

## [1.0.124] — 2026-07-26

### Changed
- Edge glow is point-anchored to the hatch’s left edge (summed overshield “max” as it builds from the right), so it moves automatically when absorbs are added or depleted
- Uses Shield-Overshield on a raised holder for a clearer vertical edge; absorb-change events update all matching party frames, not only player

## [1.0.123] — 2026-07-26

### Fixed
- Regression: OnShow hooks were detaching Blizzard absorb before we could measure/draw — Barrier/PW:S showed nothing
- Cache FillBar width first, draw owned hatch+glow, then soft-hide Blizzard (never strip if we cannot replace)
- Stop killing `totalAbsorb` / overlay on OnShow

## [1.0.122] — 2026-07-26

### Fixed
- **Approach change:** stop anchoring glow to Blizzard absorb regions (Barrier StatusBar/shadow kept winning)
- Hide all Blizzard absorb chrome, then draw **one owned hatch + glow** sized to max(known aura sum, calculator, widest Blizzard width snapshot)
- Glow is always created with that hatch — priest and mage share the same path

## [1.0.121] — 2026-07-26

### Fixed
- **Root cause of mage glow stuck on Barrier:** glow inset math skipped values `<= 1`, so a full-width total hatch (inset 0) was ignored and the shorter Barrier edge won
- Hide Blizzard `TotalAbsorbLeftShadow` (Barrier-sized) so it can’t look like our glow
- Prefer the **widest right-aligned** absorb chunk when choosing the glow edge

## [1.0.120] — 2026-07-26

### Fixed
- Glow uses the **leftmost** edge among all Blizzard absorb visuals (full hatch), not `TotalAbsorbLeftShadow` / StatusBar which only track Blazing Barrier
- Priest glow: apply from Blizzard hatch before secret-absorb “clear” logic can wipe party frames that still show a hatch

## [1.0.119] — 2026-07-26

### Fixed
- Glow follows **total** absorb (Barrier + PW:S), not just Blazing Barrier — anchor to `TotalAbsorbLeftShadow` / `totalAbsorbOverlay` instead of the StatusBar fill
- Hide Barrier-sized StatusBar solid fill when the tiled overlay shows the fuller hatch
- Raise glow on a holder frame so it stays visible on white priest health bars

## [1.0.118] — 2026-07-26

### Fixed
- Lua error `attempt to call a nil value` at ApplyGlowOnBlizzHatch: define GetBlizzAbsorbHatchRegion before it is called

## [1.0.117] — 2026-07-26

### Fixed
- Glow now pins to **Blizzard’s absorb hatch left edge** instead of a guessed width — fixes mage glow sitting short of the real shield and missing priest glow
- Stop detaching/replacing Blizzard Shield-Overlay (it sizes correctly with secret absorbs); only hide the default overAbsorbGlow

## [1.0.116] — 2026-07-26

### Fixed
- Glow aligns to the full overshield: snapshot Blizzard’s secret-sized absorb pixel width before detaching it, then draw our hatch+glow to that width
- Priest glow: always draw a crisp edge marker on any hatch; apply from Blizzard width alone when aura amounts are unreadable
- Strip all Shield-/Absorb textures under compact frames so Blizzard’s wider hatch can’t sit under a shorter glow

## [1.0.115] — 2026-07-26

### Fixed
- Glow no longer sits inside the hatch: pin the glow’s right edge to the hatch’s left edge (Shield-Overshield’s bright column was inset in the 16px texture)

## [1.0.114] — 2026-07-26

### Fixed
- Glow always draws on the hatch’s left edge whenever a hatch is shown (priest PW:S no longer skips glow)
- Mage glow no longer sits short of the real shield: stop replacing larger calculator absorb with the ~25% Barrier estimate; hatch and glow share one clip-relative left edge

## [1.0.113] — 2026-07-26

### Fixed
- Priest / party hatch now gets the left-edge glow when the calculator reports overshield as 0 but a known absorb aura (e.g. Power Word: Shield) is present

## [1.0.112] — 2026-07-26

### Fixed
- Priest / party shields (e.g. Power Word: Shield) show again when aura points or UnitGetTotalAbsorbs are secret — estimate from max health or bar-width fraction
- White Shield-Fill stub past compact frame borders: never restore Blizzard absorb while ShieldFrames is enabled; keep frame clipping + detach on clear/fail
- Party UnitHealthMax fallback reads StatusBar extents when unit APIs are secret

## [1.0.111] — 2026-07-26

### Fixed
- Glow returns to the **left edge** of the reverse-fill overshield (health left→right, shield right→left); glow only when overshield is present
- Clarified layout: one summed hatch from the right, glow on the hatch’s inner edge

## [1.0.110] — 2026-07-26

### Fixed
- Glow moves to the **right tip** of the hatch (Blizzard-style) so the striped bar no longer continues past the glow
- Removed bootstrap tint/stretch path that stacked a second hatch on party frames
- Harder Blizzard absorb detach (clear points + zero size on the sink) to stop white Shield-Fill past the border

## [1.0.109] — 2026-07-26

### Fixed
- Lua error on compact frame tick: skip non-frame `flowFrames` entries like `"linebreak"`

## [1.0.108] — 2026-07-26

### Fixed
- Barrier-only overshield: glow width scales down with short hatches (~25% max HP) so a 28px glow no longer swallows the shield and reads as a harsh slab
- Glow re-anchored to the hatch (natural texcoords, no flip) so height stays inside the bar

## [1.0.107] — 2026-07-26

### Fixed
- White bleed: Blizzard `totalAbsorb` / Shield-Fill is reparented off the unit frame while ShieldFrames owns it (hide/alpha still lost the redraw race)
- Harsh glow cut: horizontally flip `Shield-Overshield` so its soft edge faces the hatch (texture is authored for the right tip)

## [1.0.106] — 2026-07-26

### Fixed
- White bleed past party borders: enable `SetClipsChildren` on the compact unit frame only (never the health StatusBar) while overshield is shown
- Harsh health→overshield cut at the glow: wider softer glow, hatch leading edge inset so the Overshield texture feathers the seam

## [1.0.105] — 2026-07-26

### Fixed
- Party overshield bleed (white/hatch past the border): ShieldFrames now always owns compact absorb drawing — Blizzard `totalAbsorb` / `Shield-Fill` is stripped on every heal-prediction update (not only after we mark the frame active), and compact updates run immediately instead of deferred

## [1.0.104] — 2026-07-26

### Fixed
- Party health going black: overshield clip is parented to the unit frame, not the health StatusBar (a full-size clipping child of a StatusBar blanks the fill)
- Force `SetClipsChildren(false)` on compact health bars every apply to clear leftover 1.0.101 state

## [1.0.103] — 2026-07-26

### Fixed
- Glow sits 4px left over the hatch seam so the hatch’s leading lip no longer peeks ahead of the glow bar

## [1.0.102] — 2026-07-26

### Fixed
- Party frames turning solid black after gaining a shield: `SetClipsChildren` must never be applied to compact frames or their health StatusBars (it blanks the health fill)

## [1.0.101] — 2026-07-26

### Fixed
- White bleed past compact borders: stop breaking Blizzard absorb anchors (`ClearAllPoints`/`SetWidth` on `totalAbsorb` was causing Shield-Fill to stick out)
- Enable `SetClipsChildren` on the compact frame + health bar while ShieldFrames owns the overlay so any remaining Blizzard fill can’t paint past the black border
- Clamp Blizzard absorb bars that extend past the health bar even when ShieldFrames is not drawing

## [1.0.100] — 2026-07-26

### Fixed
- Overshield redrawn as a single clipped hatch texture (StatusBar path removed) so layers can’t stack or paint past the frame
- Blizzard `totalAbsorb` / `Shield-Fill` force-nuked on show, on fill-bar updates, and on a short tick while ShieldFrames owns the frame
- Glow locked to the hatch texture’s left edge

## [1.0.99] — 2026-07-26

### Fixed
- White `Shield-Fill` no longer bleeds past compact frame borders — Blizzard absorb bars/overlays are force-hidden whenever ShieldFrames owns the frame
- Dropped stacked tint/overlay layers; overshield is a single reverse-fill hatch
- Glow anchors to the hatch fill’s inner edge so it can’t sit mid-overshield

## [1.0.98] — 2026-07-26

### Fixed
- Lua error `attempt to call a nil value` in stripe apply (`ApplyTiledStatusBarFill` used before its local definition) that aborted updates and left a flooded hatch
- Failed updates now clear the overlay instead of leaving a partial apply on the bar

## [1.0.97] — 2026-07-26

### Fixed
- Overshield hatch is drawn on the reverse-fill StatusBar texture itself (no separate SetWidth overlay), so the stripe can’t desync and flood the whole health bar

## [1.0.96] — 2026-07-26

### Fixed
- Overshield stripe no longer floods the whole health bar — width is absorb÷max×bar only (status-bar `fill:GetWidth()` is the full bar, not the filled portion)

## [1.0.95] — 2026-07-26

### Fixed
- Dual-shield glow alignment: stripe and glow now share one display width (max of fill vs computed), so the glow sits on the hatch’s inner edge instead of a shorter Barrier-only width

## [1.0.94] — 2026-07-26

### Fixed
- Overshield glow aligns to the stripe’s inner edge using the stripe’s laid-out width (no hatched sliver past the glow)

## [1.0.93] — 2026-07-26

### Fixed
- Multiple absorbs (e.g. Blazing Barrier + Power Word: Shield) are summed for stripe width instead of using only one aura
- Overshield glow pins to the inner edge of the combined reverse-fill (from bar right − width), so it no longer sits on the far right tip while the stripe floats

## [1.0.92] — 2026-07-26

### Fixed
- Sticky player/party overshield after barrier fades: OOC player clear requires a live barrier aura (lingering Blizzard glow / secret absorb no longer keep the stripe)
- Dropping Blazing Barrier clears player + compact self frames immediately via `UNIT_AURA`

## [1.0.91] — 2026-07-26

### Fixed
- Mage Blazing Barrier sizing no longer uses tiny wrong aura points (dummy coeffs / leftovers) — falls back to ~25% max health
- Leave-combat / aura-drop clear no longer keeps a sticky stripe from last absorb amount or custom overlay alone

## [1.0.90] — 2026-07-26

### Fixed
- Sticky overshield after barrier fades: secret calculator values / cached aura alone no longer keep the stripe
- Clear path resets absorb cache; persist secret absorbs only with live glow, live aura, combat evidence, or a short post-event grace

## [1.0.89] — 2026-07-26

### Fixed
- Group Blazing Barrier flicker: faded Blizzard glow is no longer treated as “no shield,” which was clearing the custom overlay in a loop
- Secret absorb in groups no longer trips `clear-no-absorb` without a readable zero / depleted aura
- Keep last absorb / aura cache while Midnight secrets barrier auras; Mage barriers can estimate size from max health when needed

## [1.0.88] — 2026-07-26

### Fixed
- Overshield overlay no longer stretch-anchors to NaN/secret fill widths (group combat “screen-wide stripe” + lag)
- Status-bar path requires finite readable absorb + max (uses last known values); secret `SetValue`/`SetMinMaxValues` removed
- `SafeNumber` rejects NaN/Inf so bad widths cannot bypass `> 0` clamps
- Bootstrap no longer poisons cached bar width with the 48px stripe fallback

## [1.0.87] — 2026-07-26

### Changed
- Replaced WowUp Hub gallery with three new high-res previews (colored overshield, cyan overshield, settings)

## [1.0.86] — 2026-07-26

### Changed
- Release bump so WowUp Hub re-indexes GitHub social preview thumbnail art

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
