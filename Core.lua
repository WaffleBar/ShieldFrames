local addonName, ns = ...

local GLOW_EDGE_OFFSET = 0
local OVERLAY_TILE_SIZE = 32
local GLOW_TEXTURE_WIDTH = 16
local healPredictionCalculator

local function GetAddonMetadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, field)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addonName, field)
    end
end

ns.defaults = {
    enabled = true,
    overlayOpacity = 40,
    overlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    showGlow = true,
    glowOpacity = 60,
    glowColor = { r = 0.45, g = 0.92, b = 1.0 },
}

ShieldFramesDB = ShieldFramesDB or {}

local function GetDB()
    return ShieldFramesDB
end

local function MergeDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            db[key] = db[key] or {}
            MergeDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

function ns.GetDB()
    return GetDB()
end

function ns.MergeDefaults()
    MergeDefaults(GetDB(), ns.defaults)
end

local function MigrateOpacitySetting(db, key)
    local value = db[key]
    if type(value) ~= "number" then
        return
    end

    if value > 0 and value <= 1 then
        db[key] = math.floor(value * 100 + 0.5)
    end
end

function ns.MigrateSavedSettings()
    local db = GetDB()
    MergeDefaults(db, ns.defaults)
    MigrateOpacitySetting(db, "overlayOpacity")
    MigrateOpacitySetting(db, "glowOpacity")
end

local function NormalizeOpacityPercent(value, default)
    if type(value) ~= "number" then
        return default
    end

    if value > 0 and value <= 1 then
        return math.floor(value * 100 + 0.5)
    end

    return value
end

local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then
        return fallback
    end

    return {
        r = color.r or fallback.r,
        g = color.g or fallback.g,
        b = color.b or fallback.b,
    }
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- Reject nil/secret and non-finite numbers (NaN/Inf). NaN fails every comparison
-- (`nan > 0` is false), so unguarded width math can skip clamps and stretch overlays.
local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function SafeNumber(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    if not IsFiniteNumber(value) then
        return nil
    end
    return value
end

local function IsPositiveFinite(value)
    local n = SafeNumber(value)
    return n ~= nil and n > 0
end

-- Midnight can mark StatusBar:GetWidth() secret even when the bar is laid out.
-- Prefer GetWidth, then GetRect, then parent/frame fallbacks.
local function SafeRegionWidth(region)
    if not region then
        return nil
    end
    local width = SafeNumber(region.GetWidth and region:GetWidth())
    if IsPositiveFinite(width) then
        return width
    end
    if region.GetRect then
        local ok, _, _, rectWidth = pcall(region.GetRect, region)
        if ok then
            rectWidth = SafeNumber(rectWidth)
            if IsPositiveFinite(rectWidth) then
                return rectWidth
            end
        end
    end
    if region.GetScaledRect then
        local ok, _, _, rectWidth = pcall(region.GetScaledRect, region)
        if ok then
            rectWidth = SafeNumber(rectWidth)
            if IsPositiveFinite(rectWidth) then
                return rectWidth
            end
        end
    end
    return nil
end

-- Midnight: never `if secretBool` / `and secretBool` — compare explicitly.
local function SafeBool(value)
    if value == nil or IsSecret(value) then
        return false
    end
    return value == true
end

local function SafeUnitIsUnit(unitA, unitB)
    if unitA == nil or unitB == nil then
        return false
    end
    if unitA == unitB then
        return true
    end
    if type(UnitIsUnit) ~= "function" then
        return false
    end
    local ok, result = pcall(UnitIsUnit, unitA, unitB)
    if not ok then
        return false
    end
    return SafeBool(result)
end

local function CanAccessValue(value)
    if value == nil then
        return false
    end
    if not IsSecret(value) then
        return true
    end
    return canaccessvalue and canaccessvalue(value)
end

local function HasMidnightRenderAbsorb(absorbAmount, secretAbsorb)
    if absorbAmount ~= nil and (CanAccessValue(absorbAmount) or IsSecret(absorbAmount)) then
        return true
    end
    return secretAbsorb ~= nil
end

local function PickMidnightRenderAbsorb(absorbAmount, secretAbsorb)
    if absorbAmount ~= nil and (CanAccessValue(absorbAmount) or IsSecret(absorbAmount)) then
        return absorbAmount
    end
    return secretAbsorb
end

local function SafeAuraField(aura, field)
    if not aura or not field then
        return nil
    end

    local ok, value = pcall(function()
        return aura[field]
    end)
    if not ok then
        return nil
    end

    return value
end

local function SafeAuraSpellId(aura)
    local spellId = SafeAuraField(aura, "spellId")
    if spellId == nil or not CanAccessValue(spellId) then
        return nil
    end

    return spellId
end

local function IsFrameForbidden(frame)
    return frame and type(frame.IsForbidden) == "function" and frame:IsForbidden()
end

local function GetOverlayParentFrame(frame, healthBar)
    if healthBar and not IsFrameForbidden(healthBar) then
        return healthBar
    end
    return frame
end

local function GetOverlayAnchorFrame(frame, healthBar)
    return healthBar or frame
end

local function SafeCompare(fn)
    local ok, result = pcall(fn)
    if not ok then
        return nil
    end
    return result
end

local function SafeGreaterThan(value, threshold)
    if not CanAccessValue(value) then
        return nil
    end
    return SafeCompare(function()
        return value > threshold
    end)
end

local function SafeLessOrEqual(value, threshold)
    if not CanAccessValue(value) then
        return nil
    end
    return SafeCompare(function()
        return value <= threshold
    end)
end

local function SafeSubtractClampNonNegative(a, b)
    if not CanAccessValue(a) or not CanAccessValue(b) then
        return nil
    end
    return SafeCompare(function()
        local amount = a - b
        if amount < 0 then
            amount = 0
        end
        return amount
    end)
end

local function UsesHealPredictionCalculator()
    return CreateUnitHealPredictionCalculator ~= nil and UnitGetDetailedHealPrediction ~= nil
end

local function EnsureHealPredictionCalculator()
    if healPredictionCalculator then
        return healPredictionCalculator
    end
    if not CreateUnitHealPredictionCalculator then
        return nil
    end

    healPredictionCalculator = CreateUnitHealPredictionCalculator()
    if healPredictionCalculator.SetToDefaults then
        healPredictionCalculator:SetToDefaults()
    end
    if healPredictionCalculator.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
        healPredictionCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
    end

    return healPredictionCalculator
end

local function UpdateHealPredictionCalculator(unit)
    local calculator = EnsureHealPredictionCalculator()
    if not calculator or not UnitGetDetailedHealPrediction then
        return nil
    end

    if calculator.Reset then
        calculator:Reset()
    end

    local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calculator)
    if not ok then
        ok = pcall(UnitGetDetailedHealPrediction, unit, calculator)
    end
    if not ok then
        return nil
    end

    return calculator
end

local function GetCalculatorAbsorbValues(unit)
    local calculator = UpdateHealPredictionCalculator(unit)
    if not calculator then
        return
    end

    -- Total absorb drives the reverse-fill bar; in-bar clamp reveals overshield via subtraction.
    local totalAbsorb
    if calculator.GetTotalDamageAbsorbs then
        totalAbsorb = calculator:GetTotalDamageAbsorbs()
    end
    if totalAbsorb == nil and calculator.GetDamageAbsorbs then
        totalAbsorb = calculator:GetDamageAbsorbs()
    end

    local inBarAbsorb
    if calculator.GetDamageAbsorbs then
        inBarAbsorb = calculator:GetDamageAbsorbs()
    end

    local maxHealth = calculator.GetMaximumHealth and calculator:GetMaximumHealth()
    local overshieldAmount = SafeSubtractClampNonNegative(totalAbsorb, inBarAbsorb)

    return totalAbsorb, overshieldAmount, maxHealth, calculator
end

local function IsPositiveAmount(value)
    return SafeGreaterThan(value, 0)
end

local function FrameShowsOvershieldGlow(frame)
    local glow = frame.overAbsorbGlow
    if not glow or (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
        return false
    end
    -- Use IsShown only. We may SetAlpha(0) to hide Blizzard's glow under our stripe;
    -- that must not count as "no overshield" or we clear → restore → flicker.
    return glow:IsShown()
end

local function FrameHasBlizzOvershieldGlow(frame)
    local ok, active = pcall(FrameShowsOvershieldGlow, frame)
    return ok and active
end

local function FrameHasRawOvershieldGlow(frame)
    local glow = frame and frame.overAbsorbGlow
    if not glow or IsFrameForbidden(glow) then
        return false
    end
    return glow:IsShown()
end

local function HasSecretAbsorbValue(totalAbsorb, overshieldAmount)
    if totalAbsorb ~= nil and not CanAccessValue(totalAbsorb) then
        return true
    end
    if overshieldAmount ~= nil and not CanAccessValue(overshieldAmount) then
        return true
    end
    return false
end

local function SetFrameOvershieldActive(frame, active)
    frame.ShieldFramesOvershieldActive = active or nil
end

local function HideBlizzOvershieldGlow(frame, glow)
    if not glow or (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
        return
    end
    if frame then
        frame.ShieldFramesBlizzGlowFaded = true
    end
    glow:SetAlpha(0)
end

local function RestoreBlizzOvershieldGlow(frame, glow)
    if not glow or (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
        return
    end
    if frame then
        frame.ShieldFramesBlizzGlowFaded = nil
    end
    glow:SetAlpha(1)
    glow:Hide()
end

local function GetUnitHealthValues(frame, unit)
    local healthBar = frame and (frame.healthbar or frame.healthBar)
    local curHealth
    local maxHealth

    if unit then
        local rawCur = UnitHealth(unit)
        local rawMax = UnitHealthMax(unit)
        curHealth = rawCur ~= nil and CanAccessValue(rawCur) and SafeNumber(rawCur) or nil
        maxHealth = rawMax ~= nil and CanAccessValue(rawMax) and SafeNumber(rawMax) or nil
    end

    -- Party/raid UnitHealthMax is often secret in Midnight. Prefer the StatusBar extents
    -- when those values are still readable so absorb estimates can size a hatch.
    if (not curHealth or not maxHealth) and healthBar and not IsFrameForbidden(healthBar) then
        local ok, barCur, barMax = pcall(function()
            return healthBar:GetValue(), select(2, healthBar:GetMinMaxValues())
        end)
        if ok then
            if not curHealth and barCur ~= nil and CanAccessValue(barCur) then
                curHealth = SafeNumber(barCur)
            end
            if not maxHealth and barMax ~= nil and CanAccessValue(barMax) then
                maxHealth = SafeNumber(barMax)
            end
        end
    end

    return curHealth, maxHealth, healthBar
end

local function UnitHasReadableOvershield(unit, frame)
    local curHealth, maxHealth = GetUnitHealthValues(frame, unit)
    if not curHealth or not maxHealth or maxHealth <= 0 then
        return false
    end

    local rawAbsorb = UnitGetTotalAbsorbs(unit)
    if rawAbsorb == nil or not CanAccessValue(rawAbsorb) then
        return nil
    end

    local totalAbsorb = SafeNumber(rawAbsorb) or 0
    if totalAbsorb <= 0 then
        return false
    end

    local missingHealth = maxHealth - curHealth
    if missingHealth < 0 then
        missingHealth = 0
    end

    return totalAbsorb > missingHealth
end

local function UnitHasReadableAbsorb(unit)
    if not unit then
        return nil
    end

    local rawAbsorb = UnitGetTotalAbsorbs(unit)
    if rawAbsorb == nil or not CanAccessValue(rawAbsorb) then
        return nil
    end

    return (SafeNumber(rawAbsorb) or 0) > 0
end

-- Seed list only — runtime detection learns every absorb spell ID we see via
-- UnitGetTotalAbsorbs correlation and SPELL_ABSORBED, stored in ShieldFramesDB.
local SEED_ABSORB_SPELL_IDS = {
    [235313] = true, -- Blazing Barrier
    [235450] = true, -- Prismatic Barrier
    [11426] = true,  -- Ice Barrier
    [77535] = true,  -- Blood Shield (Blood DK)
    [193320] = true, -- Umbilicus Eternus absorb (after Vampiric Blood)
    [391527] = true, -- Umbilicus Eternus absorb (current)
    [48707] = true,  -- Anti-Magic Shell
    [17] = true,     -- Power Word: Shield
    [1253593] = true, -- Void Shield
    [47753] = true,  -- Divine Aegis (crit-heal absorb; Radiance / direct heals)
    [152118] = true, -- Clarity of Will
    [271466] = true, -- Luminous Barrier
    [184662] = true, -- Shield of Vengeance
    [108945] = true, -- Angelic Bulwark
}

-- Kept for sizing hints only (not for presence detection).
local MAGE_BARRIER_SPELL_IDS = {
    [235313] = true,
    [235450] = true,
    [11426] = true,
}

-- Compat alias used by older call sites / comments.
local ABSORB_AURA_SPELL_IDS = SEED_ABSORB_SPELL_IDS

-- When absorb aura points are secret (common on party frames), size from max health
-- so PW:S / barriers still show instead of vanishing.
local GENERIC_ABSORB_HEALTH_FRACTION = 0.22
local MAGE_BARRIER_HEALTH_FRACTION = 0.25
local MIN_ABSORB_POINT = 100
-- Pixel hatch when Midnight only exposes Blizzard's overAbsorbGlow tip (Blood Shield
-- aura/amount secret) and we have no prior width to reuse.
local DEFAULT_BOOTSTRAP_OVERLAY_WIDTH = 48

local function GetLearnedAbsorbSpellIds()
    local db = GetDB()
    if type(db.learnedAbsorbSpellIds) ~= "table" then
        db.learnedAbsorbSpellIds = {}
    end
    return db.learnedAbsorbSpellIds
end

local function LearnAbsorbSpellId(spellId)
    spellId = SafeNumber(spellId)
    if not spellId or spellId <= 0 then
        return false
    end
    spellId = math.floor(spellId + 0.5)
    if SEED_ABSORB_SPELL_IDS[spellId] then
        return false
    end
    local learned = GetLearnedAbsorbSpellIds()
    if learned[spellId] then
        return false
    end
    learned[spellId] = true
    return true
end

local function IsTrackedAbsorbSpellId(spellId)
    spellId = SafeNumber(spellId)
    if not spellId then
        return false
    end
    spellId = math.floor(spellId + 0.5)
    if SEED_ABSORB_SPELL_IDS[spellId] then
        return true
    end
    local learned = GetDB().learnedAbsorbSpellIds
    return type(learned) == "table" and learned[spellId] == true
end

local function SafeGetAuraBySpellID(unit, spellId)
    if not unit or not spellId or not C_UnitAuras then
        return nil
    end

    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
        if ok and aura then
            return aura
        end
    end

    if C_UnitAuras.GetAuraDataBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, spellId)
        if ok and aura then
            return aura
        end
    end

    return nil
end

local function ForEachHelpfulAura(unit, callback)
    if not unit or not callback or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return
    end
    -- Never break on a nil slot: Midnight can omit secret auras mid-list.
    -- Callback may return false to stop early (presence checks).
    for index = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
        if ok and aura then
            if callback(aura, index) == false then
                return
            end
        end
    end
end

local function GetBestAbsorbPointFromAura(aura)
    if not aura then
        return nil
    end

    local points = SafeAuraField(aura, "points")
    if not points then
        return nil
    end

    -- Absorb auras expose multiple points (absorb + dummy coefficients). Use the largest
    -- readable positive point; tiny values (e.g. 20-30 dummy) are not absorb amounts.
    local best
    local sawReadableZero = false
    for index = 1, 32 do
        local point = SafeAuraField(points, index)
        if point == nil then
            break
        end
        if CanAccessValue(point) then
            local amount = SafeNumber(point)
            if amount and amount > 0 then
                if not best or amount > best then
                    best = amount
                end
            elseif amount == 0 then
                sawReadableZero = true
            end
        end
    end

    if best and best >= MIN_ABSORB_POINT then
        return best
    end
    if sawReadableZero and not best then
        return 0
    end
    return nil
end

-- When UnitGetTotalAbsorbs is readable, any helpful aura whose points look like an
-- absorb amount is learned automatically (covers every class/spec without a hand list).
local function TryLearnAbsorbSpellsFromUnit(unit)
    if not unit then
        return
    end

    local totalAbsorb
    if UnitGetTotalAbsorbs and CanAccessValue then
        local ok, value = pcall(UnitGetTotalAbsorbs, unit)
        if ok then
            totalAbsorb = SafeNumber(value)
        end
    end
    if not IsPositiveFinite(totalAbsorb) or totalAbsorb < MIN_ABSORB_POINT then
        return
    end

    ForEachHelpfulAura(unit, function(aura)
        local spellId = SafeAuraSpellId(aura)
        if not spellId or IsTrackedAbsorbSpellId(spellId) then
            return
        end
        local point = GetBestAbsorbPointFromAura(aura)
        if point and point >= MIN_ABSORB_POINT and point <= totalAbsorb * 1.05 then
            LearnAbsorbSpellId(spellId)
        end
    end)
end

local function EstimateMageBarrierAbsorb(maxHealth)
    local maxH = SafeNumber(maxHealth)
    if not maxH or maxH <= 0 then
        return nil
    end
    return maxH * MAGE_BARRIER_HEALTH_FRACTION
end

local function EstimateGenericAbsorb(maxHealth)
    local maxH = SafeNumber(maxHealth)
    if not maxH or maxH <= 0 then
        return nil
    end
    return maxH * GENERIC_ABSORB_HEALTH_FRACTION
end

local function EstimateAbsorbForSpellId(spellId, maxHealth)
    if MAGE_BARRIER_SPELL_IDS[spellId] then
        return EstimateMageBarrierAbsorb(maxHealth)
    end
    if IsTrackedAbsorbSpellId(spellId) then
        return EstimateGenericAbsorb(maxHealth)
    end
    return nil
end

local function SanitizeKnownAbsorbAmount(spellId, fromAura, maxHealth)
    if fromAura == 0 then
        return 0
    end
    if spellId and MAGE_BARRIER_SPELL_IDS[spellId] then
        local estimate = EstimateMageBarrierAbsorb(maxHealth)
        if estimate then
            if fromAura and fromAura >= estimate * 0.05 then
                return fromAura
            end
            return estimate
        end
    end
    if fromAura and fromAura > 0 then
        return fromAura
    end
    -- Secret / missing points on absorbs (common on party frames).
    return EstimateAbsorbForSpellId(spellId, maxHealth)
end

local function GetAbsorbAmountFromAura(aura, maxHealth)
    if not aura then
        return nil
    end
    local spellId = SafeAuraSpellId(aura)
    if not spellId or not IsTrackedAbsorbSpellId(spellId) then
        return nil
    end
    local fromPoints = GetBestAbsorbPointFromAura(aura)
    local sanitized = SanitizeKnownAbsorbAmount(spellId, fromPoints, maxHealth)
    if sanitized ~= nil then
        return sanitized
    end
    return EstimateAbsorbForSpellId(spellId, maxHealth)
end

local function GetAbsorbAmountForSpellId(unit, spellId, maxHealth)
    local aura = SafeGetAuraBySpellID(unit, spellId)
    if not aura then
        return nil
    end
    return GetAbsorbAmountFromAura(aura, maxHealth)
end

-- Small proc absorbs (Divine Aegis) should not use the full generic fraction estimate
-- or they inflate the hatch and fight Blizzard's true width.
local SMALL_PROC_ABSORB_SPELL_IDS = {
    [47753] = true, -- Divine Aegis
}

local ABSORB_SNAPSHOT_TTL = 0.2
local absorbSnapshots = {}

local function InvalidateAbsorbSnapshot(unit)
    if unit then
        absorbSnapshots[unit] = nil
    end
end

local function ForEachTrackedAbsorbAura(unit, callback)
    if not unit or not callback then
        return
    end

    local seen = {}
    local foundViaSpellId = false
    local function consider(spellId, aura)
        spellId = SafeNumber(spellId)
        if not spellId or seen[spellId] then
            return
        end
        if not aura then
            aura = SafeGetAuraBySpellID(unit, spellId)
        end
        if not aura then
            return
        end
        seen[spellId] = true
        foundViaSpellId = true
        callback(aura, spellId)
    end

    for spellId in pairs(SEED_ABSORB_SPELL_IDS) do
        consider(spellId, nil)
    end
    local learned = GetDB().learnedAbsorbSpellIds
    if type(learned) == "table" then
        for spellId in pairs(learned) do
            consider(spellId, nil)
        end
    end
    -- Index scan is a fallback when spell-ID lookups miss; skip if we already found absorbs.
    if not foundViaSpellId then
        ForEachHelpfulAura(unit, function(aura)
            local spellId = SafeAuraSpellId(aura)
            if spellId and IsTrackedAbsorbSpellId(spellId) then
                consider(spellId, aura)
            end
        end)
    end
end

local function BuildAbsorbSnapshot(unit, maxHealth)
    local snap = {
        t = GetTime(),
        maxHealth = SafeNumber(maxHealth),
        hasKnown = false,
        total = nil,
        fraction = nil,
        depleted = false,
        count = 0,
    }

    local total = 0
    local sawAura = false
    local sawPositive = false
    local sawZeroOnly = true
    local fraction = 0

    ForEachTrackedAbsorbAura(unit, function(aura, spellId)
        sawAura = true
        snap.count = snap.count + 1
        snap.hasKnown = true

        local amount = GetAbsorbAmountFromAura(aura, maxHealth)
        if amount == nil and spellId then
            amount = EstimateAbsorbForSpellId(spellId, maxHealth)
        end
        if amount and amount > 0 then
            total = total + amount
            sawPositive = true
            sawZeroOnly = false
        elseif amount == 0 then
            -- depleted instance of this aura
        else
            sawZeroOnly = false
        end

        if SMALL_PROC_ABSORB_SPELL_IDS[spellId] then
            fraction = fraction + 0.08
        elseif MAGE_BARRIER_SPELL_IDS[spellId] then
            fraction = fraction + MAGE_BARRIER_HEALTH_FRACTION
        else
            fraction = fraction + GENERIC_ABSORB_HEALTH_FRACTION
        end
    end)

    if not sawAura then
        snap.total = nil
        snap.fraction = nil
        snap.depleted = false
    else
        if sawPositive then
            snap.total = total
            snap.depleted = false
        elseif sawZeroOnly then
            snap.total = 0
            snap.depleted = true
        else
            snap.total = nil
            snap.depleted = false
        end
        if fraction > 0 then
            if fraction > 0.85 then
                snap.fraction = 0.85
            else
                snap.fraction = fraction
            end
        end
    end

    absorbSnapshots[unit] = snap
    return snap
end

local function GetAbsorbSnapshot(unit, maxHealth)
    if not unit then
        return nil
    end

    maxHealth = SafeNumber(maxHealth)
    local now = GetTime()
    local snap = absorbSnapshots[unit]
    if snap and (now - snap.t) <= ABSORB_SNAPSHOT_TTL then
        if maxHealth == nil or snap.maxHealth == nil or snap.maxHealth == maxHealth then
            return snap
        end
    end
    return BuildAbsorbSnapshot(unit, maxHealth)
end

local function GetKnownAbsorbAuraData(unit)
    if not unit or not C_UnitAuras then
        return nil
    end

    -- Do NOT learn here — this runs from Blizzard FillBar/heal-prediction hooks.
    -- Direct spell lookups first: party aura index scans often miss secret absorbs.
    for spellId in pairs(SEED_ABSORB_SPELL_IDS) do
        local aura = SafeGetAuraBySpellID(unit, spellId)
        if aura then
            return aura, spellId
        end
    end
    local learned = GetDB().learnedAbsorbSpellIds
    if type(learned) == "table" then
        for spellId in pairs(learned) do
            local aura = SafeGetAuraBySpellID(unit, spellId)
            if aura then
                return aura, spellId
            end
        end
    end

    local foundAura, foundSpellId
    ForEachHelpfulAura(unit, function(aura)
        local spellId = SafeAuraSpellId(aura)
        if spellId and IsTrackedAbsorbSpellId(spellId) then
            foundAura = aura
            foundSpellId = spellId
            return false
        end
    end)
    if foundAura then
        return foundAura, foundSpellId
    end

    return nil
end

local function UnitHasKnownAbsorbAura(unit)
    local snap = GetAbsorbSnapshot(unit, nil)
    return snap ~= nil and snap.hasKnown == true
end

local function UnitHasDamageBarrierAura(unit)
    return UnitHasKnownAbsorbAura(unit)
end

-- When absolute absorb/max are secret, size the hatch as a fraction of bar width.
local function EstimateKnownAbsorbBarFraction(unit)
    local snap = GetAbsorbSnapshot(unit, nil)
    if not snap then
        return nil
    end
    return snap.fraction
end

-- Sum every tracked absorb aura currently on the unit (seed + learned).
local function GetTotalKnownAbsorbAmount(unit, maxHealth)
    local snap = GetAbsorbSnapshot(unit, maxHealth)
    if not snap then
        return nil
    end
    return snap.total
end

local function GetAbsorbFromKnownAura(unit)
    return GetTotalKnownAbsorbAmount(unit, nil)
end

local function KnownAbsorbAuraIsDepleted(unit)
    local snap = GetAbsorbSnapshot(unit, nil)
    return snap ~= nil and snap.depleted == true
end

local function UnitHasKnownAbsorbCandidate(unit)
    local snap = GetAbsorbSnapshot(unit, nil)
    if not snap or not snap.hasKnown then
        return false
    end
    return not snap.depleted
end

local function CountLearnedAbsorbSpellIds()
    local learned = GetDB().learnedAbsorbSpellIds
    if type(learned) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(learned) do
        count = count + 1
    end
    return count
end

local function IsPlayerUnitToken(unit)
    if not unit then
        return false
    end
    return unit == "player" or SafeUnitIsUnit(unit, "player")
end

local function IsCompactUnitFrame(frame)
    if type(frame) ~= "table" then
        return false
    end
    if frame.optionTable ~= nil or frame.displayedUnit ~= nil then
        return true
    end
    local name = frame.GetName and frame:GetName()
    return type(name) == "string" and name:find("Compact", 1, true) ~= nil
end

local function RefreshKnownAbsorbAuraState(frame, unit)
    if not frame or not unit then
        return
    end

    if KnownAbsorbAuraIsDepleted(unit) then
        frame.ShieldFramesKnownAbsorbAuraPresent = false
        return
    end

    if UnitHasKnownAbsorbAura(unit) then
        frame.ShieldFramesKnownAbsorbAuraPresent = true
        return
    end

    -- Failed scan: keep cache in combat only (Blood Shield aura lookups often fail).
    -- Never keep cache from a lingering Blizzard glow — that stuck the stripe OOC.
    if IsPlayerUnitToken(unit) and UnitAffectingCombat(unit) then
        return
    end

    if UnitHasReadableAbsorb(unit) == false then
        frame.ShieldFramesKnownAbsorbAuraPresent = false
        return
    end

    frame.ShieldFramesKnownAbsorbAuraPresent = false
end

local function FrameShowsAbsorbBar(frame)
    local bar = frame and frame.totalAbsorb
    if not bar or (type(bar.IsForbidden) == "function" and bar:IsForbidden()) then
        return false
    end

    return bar:IsShown()
end

local function HasRecentAbsorbEvent(frame)
    if not frame or not frame.ShieldFramesLastAbsorbEvent then
        return false
    end
    return (GetTime() - frame.ShieldFramesLastAbsorbEvent) < 12
end

local function HasFreshAbsorbEvent(frame, maxAge)
    if not frame or not frame.ShieldFramesLastAbsorbEvent then
        return false
    end
    return (GetTime() - frame.ShieldFramesLastAbsorbEvent) < (maxAge or 2)
end

local function HasLiveAbsorbVisualSignal(frame, unit)
    if unit and UnitHasKnownAbsorbCandidate(unit) then
        return true
    end
    if unit and UnitHasReadableAbsorb(unit) == true then
        return true
    end
    if FrameShowsAbsorbBar(frame) then
        return true
    end

    local glowShown = FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame)
    if not glowShown then
        return false
    end

    -- Player OOC: Blizzard can leave overAbsorbGlow shown after barrier fades in groups.
    -- Require a live barrier aura (or combat) before trusting glow alone.
    if IsPlayerUnitToken(unit) and not UnitAffectingCombat(unit) then
        return UnitHasKnownAbsorbAura(unit) == true
    end

    return true
end

local function KnownAbsorbAuraEvidenceActive(frame, unit)
    if unit and UnitHasKnownAbsorbCandidate(unit) then
        return true
    end
    if not (frame and frame.ShieldFramesKnownAbsorbAuraPresent == true) then
        return false
    end
    if unit and UnitAffectingCombat(unit) then
        return true
    end
    -- OOC: cached aura only with a fresh event (anti-flicker), not forever.
    return HasFreshAbsorbEvent(frame, 2)
end

local function FrameShowsCustomOverlay(frame)
    if not frame then
        return false
    end

    if frame.ShieldFramesOverlayBar
        and not IsFrameForbidden(frame.ShieldFramesOverlayBar)
        and frame.ShieldFramesOverlayBar:IsShown()
    then
        return true
    end

    if frame.ShieldFramesOverlay
        and not IsFrameForbidden(frame.ShieldFramesOverlay)
        and frame.ShieldFramesOverlay:IsShown()
    then
        return true
    end

    return false
end

local function HasCombatSecretAbsorbSignal(unit, totalAbsorb, overshieldAmount)
    return unit
        and UnitAffectingCombat(unit)
        and HasSecretAbsorbValue(totalAbsorb, overshieldAmount)
end

-- Persist secret absorbs only with live evidence (glow / aura / combat+cache).
-- A secret calculator value alone is NOT proof of a shield — Midnight leaves secrets around with 0 absorb.
local function ShouldPersistSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount)
    if not HasSecretAbsorbValue(totalAbsorb, overshieldAmount) then
        return false
    end
    if HasLiveAbsorbVisualSignal(frame, unit) then
        return true
    end
    if unit and UnitAffectingCombat(unit) then
        if frame and frame.ShieldFramesKnownAbsorbAuraPresent then
            return true
        end
        if frame and frame.ShieldFramesLastAbsorbAmount and frame.ShieldFramesLastAbsorbAmount > 0 then
            return true
        end
        return HasRecentAbsorbEvent(frame)
    end
    -- Brief OOC grace only while Blizzard glow is still up (anti-flicker), not after it dies.
    if HasFreshAbsorbEvent(frame, 2) and FrameHasRawOvershieldGlow(frame) and UnitHasKnownAbsorbAura(unit) then
        return true
    end
    return false
end

local function ShouldPersistCombatSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount)
    return ShouldPersistSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount)
end

local function FrameHasOvershieldVisualSignal(frame)
    if FrameShowsAbsorbBar(frame) then
        return true
    end
    return FrameHasBlizzOvershieldGlow(frame)
end

local function UnitHasActiveKnownAbsorb(unit, frame)
    if not unit then
        return false
    end

    local fromAura = GetAbsorbFromKnownAura(unit)
    if fromAura and fromAura > 0 then
        return true
    end
    if fromAura == 0 then
        return false
    end

    if UnitHasKnownAbsorbCandidate(unit) then
        return true
    end

    if UnitHasReadableAbsorb(unit) == true then
        return true
    end

    if frame and FrameShowsAbsorbBar(frame) then
        return true
    end

    return false
end

local function GetAbsorbFromBarrierAura(unit)
    return GetAbsorbFromKnownAura(unit)
end

local function GetReadableAbsorbAmount(frame, unit, calculatorAbsorb)
    if calculatorAbsorb ~= nil and CanAccessValue(calculatorAbsorb) then
        local amount = SafeNumber(calculatorAbsorb) or 0
        if amount > 0 then
            return amount
        end
    end

    if unit then
        local fromAura = GetAbsorbFromBarrierAura(unit)
        if fromAura and fromAura > 0 then
            return fromAura
        end

        local readable = UnitHasReadableAbsorb(unit)
        if readable == true then
            return SafeNumber(UnitGetTotalAbsorbs(unit)) or 0
        end
    end

    local bar = frame and frame.totalAbsorb
    if bar and not (type(bar.IsForbidden) == "function" and bar:IsForbidden()) and bar:IsShown() then
        local value = bar:GetValue()
        if value ~= nil and CanAccessValue(value) then
            return SafeNumber(value) or 0
        end
        return nil
    end

    return nil
end

local function EstimateAbsorbFromBarWidth(frame, healthBar, maxHealth)
    -- Never read Blizzard unit frame bar widths; it taints heal prediction secrets.
    return nil
end

local function EstimateAbsorbFromOvershieldContext(frame, unit, healthBar, maxHealth)
    if not frame then
        return nil
    end

    local hasGlow = FrameHasBlizzOvershieldGlow(frame)
    local hasAbsorbBar = FrameShowsAbsorbBar(frame)
    if not hasGlow and not hasAbsorbBar then
        return nil
    end

    local curHealth, resolvedMax = GetUnitHealthValues(frame, unit)
    local renderMax = maxHealth
    if not renderMax or not CanAccessValue(renderMax) then
        renderMax = resolvedMax
    end
    if not renderMax or not CanAccessValue(renderMax) then
        return nil
    end

    if frame.ShieldFramesPendingAbsorbEstimate and frame.ShieldFramesPendingAbsorbEstimate > 0 then
        return frame.ShieldFramesPendingAbsorbEstimate
    end

    local barEstimate = EstimateAbsorbFromBarWidth(frame, healthBar, renderMax)
    if barEstimate and barEstimate > 0 then
        return barEstimate
    end

    if curHealth and CanAccessValue(curHealth) and renderMax > curHealth then
        return renderMax - curHealth
    end

    if frame.ShieldFramesLastAbsorbAmount and frame.ShieldFramesLastAbsorbAmount > 0 then
        return frame.ShieldFramesLastAbsorbAmount
    end

    -- Full-HP overshield: tip glow with secret amount (common Blood Shield case).
    -- Estimate from max health so owned hatch can still size.
    if hasGlow then
        local maxH = SafeNumber(renderMax)
        if maxH and maxH > 0 then
            return maxH * GENERIC_ABSORB_HEALTH_FRACTION
        end
    end

    return nil
end

local function GetKnownAbsorbAmount(unit, frame, healthBar, maxHealth)
    if not UnitHasKnownAbsorbAura(unit) then
        return nil
    end

    local total = GetTotalKnownAbsorbAmount(unit, maxHealth)
    if total ~= nil then
        if total > 0 then
            return total
        end
        return nil
    end

    if frame and healthBar and maxHealth and CanAccessValue(maxHealth) then
        local estimated = EstimateAbsorbFromBarWidth(frame, healthBar, maxHealth)
        if estimated and estimated > 0 then
            return estimated
        end
    end

    if frame and frame.ShieldFramesPendingAbsorbEstimate and frame.ShieldFramesPendingAbsorbEstimate > 0 then
        return frame.ShieldFramesPendingAbsorbEstimate
    end

    if frame and frame.ShieldFramesLastAbsorbAmount and frame.ShieldFramesLastAbsorbAmount > 0 then
        return frame.ShieldFramesLastAbsorbAmount
    end

    return nil
end

local function GetBarrierAbsorbAmount(unit, frame, healthBar, maxHealth)
    return GetKnownAbsorbAmount(unit, frame, healthBar, maxHealth)
end

local function ShouldShowOvershieldGlow(frame, overshieldAmount, fill)
    if not fill then
        return false
    end

    local hasOvershield = IsPositiveAmount(overshieldAmount)
    if hasOvershield == true then
        return true
    end
    if hasOvershield == false then
        local unit = frame.unit or frame.displayedUnit
        if unit and UnitHasActiveKnownAbsorb(unit, frame) then
            return true
        end
        if unit and UnitHasReadableAbsorb(unit) == true then
            return true
        end
        if FrameShowsAbsorbBar(frame) then
            return true
        end
        return false
    end

    -- Secret overshield amount: follow live absorb signals / active custom overlay.
    local unit = frame.unit or frame.displayedUnit
    if unit and UnitHasActiveKnownAbsorb(unit, frame) then
        return true
    end
    if FrameShowsAbsorbBar(frame) then
        return true
    end
    if frame and frame.ShieldFramesOvershieldActive then
        return true
    end
    if FrameShowsCustomOverlay(frame) then
        return true
    end
    if unit and UnitAffectingCombat(unit) and HasRecentAbsorbEvent(frame) then
        return true
    end

    return false
end

local function HasReadableNoOvershield(unit, frame)
    local readable = UnitHasReadableOvershield(unit, frame)
    if readable == true then
        return false
    end
    if readable == false then
        return true
    end
    return false
end

local function HasActiveAbsorbEvidence(frame, unit, totalAbsorb, overshieldAmount)
    if unit and UnitHasActiveKnownAbsorb(unit, frame) then
        return true
    end

    if FrameShowsAbsorbBar(frame) then
        return true
    end

    if unit and UnitHasReadableAbsorb(unit) == true then
        return true
    end

    local readableAbsorb = GetReadableAbsorbAmount(frame, unit, totalAbsorb)
    if readableAbsorb and readableAbsorb > 0 then
        return true
    end

    if IsPositiveAmount(overshieldAmount) == true then
        return true
    end

    if SafeGreaterThan(totalAbsorb, 0) == true then
        return true
    end

    if SafeLessOrEqual(totalAbsorb, 0) == true then
        return false
    end

    -- Player OOC without a live barrier aura: not active, even if Blizz glow lingers.
    if IsPlayerUnitToken(unit) and not UnitAffectingCombat(unit) and not UnitHasKnownAbsorbAura(unit) then
        return false
    end

    if HasLiveAbsorbVisualSignal(frame, unit) then
        return true
    end

    if HasSecretAbsorbValue(totalAbsorb, overshieldAmount) then
        if ShouldPersistSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount) then
            return true
        end
        return false
    end

    return false
end

local function HasClearNoAbsorbSignal(frame, unit, totalAbsorb, overshieldAmount)
    if unit and KnownAbsorbAuraIsDepleted(unit) then
        return true
    end

    -- Player: if known absorb auras are gone and absorb reads as empty, clear immediately.
    -- Do not keep a SoftHide FillBar cache alive after self-shields expire (priest sticky hatch).
    -- Keep drawing while Blizzard's combat overAbsorbGlow is still live (Blood Shield can
    -- be fully secret — aura lookup false, readable absorb nil).
    if IsPlayerUnitToken(unit) then
        local blizzGlowLive = FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame)
        if not UnitHasKnownAbsorbAura(unit)
            and UnitHasReadableAbsorb(unit) == false
            and not FrameShowsAbsorbBar(frame)
            and not blizzGlowLive
        then
            return true
        end
        if not UnitAffectingCombat(unit)
            and not UnitHasKnownAbsorbAura(unit)
            and UnitHasReadableAbsorb(unit) ~= true
            and not FrameShowsAbsorbBar(frame)
            and not blizzGlowLive
        then
            return true
        end
    end

    if HasLiveAbsorbVisualSignal(frame, unit) then
        return false
    end

    if FrameShowsAbsorbBar(frame) then
        return false
    end

    if unit and UnitHasReadableAbsorb(unit) == true then
        return false
    end

    if KnownAbsorbAuraEvidenceActive(frame, unit) then
        return false
    end

    if SafeGreaterThan(totalAbsorb, 0) == true then
        return false
    end

    if SafeGreaterThan(overshieldAmount, 0) == true then
        return false
    end

    if SafeLessOrEqual(totalAbsorb, 0) == true then
        return true
    end

    if unit and UnitHasReadableAbsorb(unit) == false then
        return true
    end

    if HasSecretAbsorbValue(totalAbsorb, overshieldAmount) then
        if ShouldPersistSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount) then
            return false
        end
        return true
    end

    return not HasActiveAbsorbEvidence(frame, unit, totalAbsorb, overshieldAmount)
end

local function MidnightFrameHasAbsorb(frame, overshieldAmount, totalAbsorb, unit)
    return HasActiveAbsorbEvidence(frame, unit, totalAbsorb, overshieldAmount)
end

local function ResolveMidnightRenderValues(frame, unit, totalAbsorb, maxHealth, healthBar)
    local _, resolvedMax = GetUnitHealthValues(frame, unit)
    if resolvedMax and CanAccessValue(resolvedMax) then
        maxHealth = resolvedMax
    end

    local secretAbsorb
    if totalAbsorb ~= nil and not CanAccessValue(totalAbsorb) then
        secretAbsorb = totalAbsorb
    end

    local absorbAmount = GetReadableAbsorbAmount(frame, unit, totalAbsorb)
    if absorbAmount ~= nil and not CanAccessValue(absorbAmount) then
        secretAbsorb = absorbAmount
        absorbAmount = nil
    end
    if (absorbAmount == nil or absorbAmount <= 0) and frame and healthBar and maxHealth and CanAccessValue(maxHealth) then
        local estimated = EstimateAbsorbFromBarWidth(frame, healthBar, maxHealth)
        if estimated and estimated > 0 then
            absorbAmount = estimated
        end
    end

    if (absorbAmount == nil or absorbAmount <= 0) and frame and frame.ShieldFramesPendingAbsorbEstimate then
        if FrameShowsAbsorbBar(frame) or (unit and UnitHasKnownAbsorbCandidate(unit)) then
            absorbAmount = frame.ShieldFramesPendingAbsorbEstimate
        end
    end

    if (absorbAmount == nil or absorbAmount <= 0) and unit then
        local fromKnownAura = GetKnownAbsorbAmount(unit, frame, healthBar, maxHealth)
        if fromKnownAura and fromKnownAura > 0 then
            absorbAmount = fromKnownAura
        end
    end

    if (absorbAmount == nil or absorbAmount <= 0)
        and frame
        and frame.ShieldFramesLastAbsorbAmount
        and frame.ShieldFramesLastAbsorbAmount > 0
    then
        if KnownAbsorbAuraEvidenceActive(frame, unit)
            or FrameHasBlizzOvershieldGlow(frame)
            or ShouldPersistSecretAbsorb(frame, unit, totalAbsorb, secretAbsorb or totalAbsorb)
        then
            absorbAmount = frame.ShieldFramesLastAbsorbAmount
        end
    end

    if (absorbAmount == nil or absorbAmount <= 0) and frame and FrameHasBlizzOvershieldGlow(frame) then
        local estimated = EstimateAbsorbFromOvershieldContext(frame, unit, healthBar, maxHealth)
        if estimated and estimated > 0 then
            absorbAmount = estimated
        end
    end

    -- Prefer known-aura totals when the calculator absorb is missing, but never
    -- shrink a larger readable absorb (Barrier estimates are ~25% max HP and were
    -- pulling the glow short of the real shield width).
    if unit and UnitHasKnownAbsorbAura(unit) then
        local totalKnown = GetTotalKnownAbsorbAmount(unit, maxHealth)
        if totalKnown and totalKnown > 0 then
            if absorbAmount == nil or absorbAmount <= 0 then
                absorbAmount = totalKnown
            else
                local readable = SafeNumber(absorbAmount)
                if readable and totalKnown > readable then
                    absorbAmount = totalKnown
                end
            end
        elseif (absorbAmount == nil or absorbAmount <= 0) and maxHealth and CanAccessValue(maxHealth) then
            local fraction = EstimateKnownAbsorbBarFraction(unit)
            if fraction and fraction > 0 then
                local maxH = SafeNumber(maxHealth)
                if maxH and maxH > 0 then
                    absorbAmount = maxH * fraction
                end
            end
        end
    end

    return absorbAmount, maxHealth, secretAbsorb
end

local function IsEnabled()
    return GetDB().enabled ~= false
end

local function GetOverlaySettings()
    local db = GetDB()
    local overlayPercent = NormalizeOpacityPercent(db.overlayOpacity, ns.defaults.overlayOpacity)
    local glowPercent = NormalizeOpacityPercent(db.glowOpacity, ns.defaults.glowOpacity)
    return {
        overlayAlpha = overlayPercent / 100,
        overlayColor = NormalizeColor(db.overlayColor, ns.defaults.overlayColor),
        showGlow = db.showGlow ~= false,
        glowAlpha = glowPercent / 100,
        glowColor = NormalizeColor(db.glowColor, ns.defaults.glowColor),
    }
end

local function GetOverlayTintColor(settings)
    return settings.glowColor or ns.defaults.glowColor
end

local BLIZZ_ABSORB_OVERLAY_KEYS = {
    "totalAbsorbOverlay",
    "totalAbsorbBarOverlay",
}

local BLIZZ_ABSORB_BAR_KEYS = {
    "totalAbsorb",
    "totalAbsorbBar",
}

local absorbSinkFrame

local function GetAbsorbSinkFrame()
    if not absorbSinkFrame then
        absorbSinkFrame = CreateFrame("Frame", nil, UIParent)
        absorbSinkFrame:Hide()
        absorbSinkFrame:SetSize(1, 1)
        absorbSinkFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
    end
    return absorbSinkFrame
end

local function DetachBlizzAbsorbRegion(region)
    if not region or (type(region.IsForbidden) == "function" and region:IsForbidden()) then
        return false
    end

    if not region.ShieldFramesSFParent then
        local parent = region.GetParent and region:GetParent()
        if parent and parent ~= GetAbsorbSinkFrame() then
            region.ShieldFramesSFParent = parent
        end
    end

    local sink = GetAbsorbSinkFrame()
    if region.GetParent and region:GetParent() ~= sink then
        region:SetParent(sink)
    end
    region:Hide()
    if region.ClearAllPoints then
        region:ClearAllPoints()
    end
    if region.SetSize then
        region:SetSize(0.001, 0.001)
    elseif region.SetWidth and region.SetHeight then
        region:SetWidth(0.001)
        region:SetHeight(0.001)
    end
    if region.SetAlpha then
        region:SetAlpha(0)
    end
    if region.SetVertexColor then
        region:SetVertexColor(0, 0, 0, 0)
    end
    return true
end

local function RestoreDetachedBlizzAbsorbRegion(region)
    if not region or not region.ShieldFramesSFParent then
        return
    end
    if not (type(region.IsForbidden) == "function" and region:IsForbidden()) then
        region:SetParent(region.ShieldFramesSFParent)
        if region.SetAlpha then
            region:SetAlpha(1)
        end
        if region.SetVertexColor then
            region:SetVertexColor(1, 1, 1, 1)
        end
    end
    region.ShieldFramesSFParent = nil
end

local function HideBlizzAbsorbBar(bar, frame)
    if not DetachBlizzAbsorbRegion(bar) then
        return false
    end
    if bar.overlay then
        DetachBlizzAbsorbRegion(bar.overlay)
    end
    if frame then
        frame.ShieldFramesBlizzAbsorbHidden = true
    end
    return true
end

local function SuppressBlizzAbsorbBars(frame, healthBar)
    for _, key in ipairs(BLIZZ_ABSORB_BAR_KEYS) do
        HideBlizzAbsorbBar(frame and frame[key], frame)
        if healthBar then
            HideBlizzAbsorbBar(healthBar[key], frame)
        end
    end
end

local function RestoreBlizzAbsorbBars(frame, healthBar, force)
    -- While ShieldFrames is enabled, never hand Blizzard Shield-Fill back — restoring
    -- it is what paints the white stub past the compact frame border.
    if IsEnabled() and not force then
        return
    end

    if not frame or not frame.ShieldFramesBlizzAbsorbHidden then
        return
    end

    for _, key in ipairs(BLIZZ_ABSORB_BAR_KEYS) do
        RestoreDetachedBlizzAbsorbRegion(frame[key])
        local bar = frame[key]
        if bar and bar.overlay then
            RestoreDetachedBlizzAbsorbRegion(bar.overlay)
        end
        if healthBar then
            RestoreDetachedBlizzAbsorbRegion(healthBar[key])
            bar = healthBar[key]
            if bar and bar.overlay then
                RestoreDetachedBlizzAbsorbRegion(bar.overlay)
            end
        end
    end

    RestoreDetachedBlizzAbsorbRegion(frame.totalAbsorbOverlay)
    if healthBar then
        RestoreDetachedBlizzAbsorbRegion(healthBar.totalAbsorbOverlay)
    end

    frame.ShieldFramesBlizzAbsorbHidden = nil
end

local function SuppressBlizzAbsorbOverlays(frame, healthBar)
    -- Keep Blizzard Shield-Overlay hatch visible (secret absorb sizing). Do not detach.
end

local function SuppressAllBlizzAbsorbVisuals(frame, healthBar)
    -- Only hide Blizzard's default right-edge overshield glow.
    local glow = frame and frame.overAbsorbGlow
    if glow then
        HideBlizzOvershieldGlow(frame, glow)
    end
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function GetOvershieldAmount(unit, curHealth, maxHealth)
    if not unit or not curHealth or not maxHealth or curHealth <= 0 or maxHealth <= 0 then
        return 0
    end

    local totalAbsorb = UnitGetTotalAbsorbs(unit) or 0
    totalAbsorb = SafeNumber(totalAbsorb) or 0
    if totalAbsorb <= 0 then
        return 0
    end

    local missingHealth = maxHealth - curHealth
    if missingHealth < 0 then
        missingHealth = 0
    end

    local overshield = totalAbsorb - missingHealth
    if overshield <= 0 then
        return 0
    end

    return overshield, totalAbsorb
end

local function EnsureCustomTextures(frame, healthBar)
    local parent = GetOverlayParentFrame(frame, healthBar)

    if not frame.ShieldFramesOverlay then
        local tint = parent:CreateTexture(nil, "OVERLAY", nil, 5)
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:Hide()

        local overlay = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        overlay.tileSize = OVERLAY_TILE_SIZE
        overlay:SetDrawLayer("OVERLAY", 6)
        overlay:Hide()

        local glow = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        glow:SetBlendMode("ADD")
        glow:SetWidth(GLOW_TEXTURE_WIDTH)
        glow:SetDrawLayer("OVERLAY", 7)
        glow:Hide()

        frame.ShieldFramesTint = tint
        frame.ShieldFramesOverlay = overlay
        frame.ShieldFramesGlow = glow
    else
        if frame.ShieldFramesTint then
            frame.ShieldFramesTint:SetParent(parent)
        end
        if frame.ShieldFramesOverlay then
            frame.ShieldFramesOverlay:SetParent(parent)
        end
        if frame.ShieldFramesGlow then
            frame.ShieldFramesGlow:SetParent(parent)
        end
    end

    return frame.ShieldFramesOverlay, frame.ShieldFramesGlow
end

local function SetFrameClipOverflow(frame, healthBar, enabled)
    -- Never clip the health StatusBar (blanks the fill). Clipping the compact unit
    -- frame itself is safe and stops Blizzard Shield-Fill painting past the border.
    -- Do NOT clip Player/Target/Focus: cast bars and icons hang outside those frames.
    if healthBar and healthBar.SetClipsChildren then
        healthBar:SetClipsChildren(false)
    end

    if not frame or not frame.SetClipsChildren then
        return
    end

    if enabled and not IsCompactUnitFrame(frame) then
        enabled = false
    end

    if enabled then
        if frame.ShieldFramesFrameClipsSaved == nil then
            local wasClipping = false
            if frame.GetClipsChildren then
                local ok, clips = pcall(frame.GetClipsChildren, frame)
                if ok and not IsSecret(clips) then
                    wasClipping = clips == true
                end
            end
            frame.ShieldFramesFrameClipsSaved = wasClipping
        end
        frame:SetClipsChildren(true)
        frame.ShieldFramesForcedFrameClip = true
    else
        if frame.ShieldFramesFrameClipsSaved ~= nil then
            frame:SetClipsChildren(frame.ShieldFramesFrameClipsSaved)
            frame.ShieldFramesFrameClipsSaved = nil
        elseif frame.ShieldFramesForcedFrameClip then
            frame:SetClipsChildren(false)
        end
        frame.ShieldFramesForcedFrameClip = nil
        frame.ShieldFramesHealthClipsSaved = nil
        frame.ShieldFramesForcedHealthClip = nil
    end
end

local function HideOvershieldDisplay(frame)
    if frame.ShieldFramesTint then
        frame.ShieldFramesTint:Hide()
    end
    if frame.ShieldFramesOverlay then
        frame.ShieldFramesOverlay:Hide()
    end
    if frame.ShieldFramesGlow then
        frame.ShieldFramesGlow:Hide()
    end
    if frame.ShieldFramesEdgeGlow then
        frame.ShieldFramesEdgeGlow:Hide()
    end
    if frame.ShieldFramesEdgeGlowSoft then
        frame.ShieldFramesEdgeGlowSoft:Hide()
    end
    if frame.ShieldFramesEdgeGlowStrips then
        for _, strip in ipairs(frame.ShieldFramesEdgeGlowStrips) do
            strip:Hide()
        end
    end
    if frame.ShieldFramesGlowHolder and not IsFrameForbidden(frame.ShieldFramesGlowHolder) then
        frame.ShieldFramesGlowHolder:Hide()
    end
    if frame.ShieldFramesOverlayBar and not IsFrameForbidden(frame.ShieldFramesOverlayBar) then
        frame.ShieldFramesOverlayBar:Hide()
    end
    if frame.ShieldFramesOverlayClip and not IsFrameForbidden(frame.ShieldFramesOverlayClip) then
        frame.ShieldFramesOverlayClip:Hide()
    end
    local healthBar = frame.healthbar or frame.healthBar
    -- Keep compact-frame clipping + Blizzard absorb suppressed while the addon is on.
    -- Restoring Blizzard absorb here reintroduced the white stub past the border.
    if IsEnabled() then
        SetFrameClipOverflow(frame, healthBar, true)
        SuppressAllBlizzAbsorbVisuals(frame, healthBar)
    else
        SetFrameClipOverflow(frame, healthBar, false)
        RestoreBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
        RestoreBlizzAbsorbBars(frame, healthBar, true)
    end
    frame.ShieldFramesLastApplyPath = nil
    frame.ShieldFramesLastBootstrapMode = nil
    frame.ShieldFramesLastRenderMaxHealth = nil
end

local function ClearFrameOvershieldState(frame)
    if not frame then
        return
    end
    SetFrameOvershieldActive(frame, false)
    frame.ShieldFramesKnownAbsorbAuraPresent = nil
    frame.ShieldFramesLastAbsorbEvent = nil
    frame.ShieldFramesLastAbsorbAmount = nil
    frame.ShieldFramesPendingAbsorbEstimate = nil
    frame.ShieldFramesLastOverlayWidth = nil
    frame.ShieldFramesBlizzAbsorbWidth = nil
    frame.ShieldFramesCachedBarWidth = nil
    frame.ShieldFramesLastMaxHealth = nil
    HideOvershieldDisplay(frame)
    frame.ShieldFramesLastApplyResult = false
end

local function EnsureOvershieldBar(frame, healthBar)
    -- Parent the clip to the unit frame (NOT the StatusBar). A full-size clipping
    -- child of a StatusBar blanks the health fill on compact party frames.
    local clipParent = frame or healthBar
    if not frame.ShieldFramesOverlayClip then
        local clip = CreateFrame("Frame", nil, clipParent)
        clip:SetClipsChildren(true)
        clip:Hide()
        frame.ShieldFramesOverlayClip = clip
    end

    -- Keep a legacy StatusBar around for older paths/debug, but the hatch is a texture now.
    if not frame.ShieldFramesOverlayBar then
        local bar = CreateFrame("StatusBar", nil, frame.ShieldFramesOverlayClip)
        bar:SetFrameLevel((healthBar and healthBar.GetFrameLevel and healthBar:GetFrameLevel() or 0) + 5)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetReverseFill(true)
        bar:Hide()
        frame.ShieldFramesOverlayBar = bar
    end

    local overlay, glow = EnsureCustomTextures(frame, healthBar)
    return frame.ShieldFramesOverlayBar, overlay, glow, frame.ShieldFramesOverlayClip
end

local function AttachBlizzAbsorbKillers(frame)
    if not frame or frame.ShieldFramesAbsorbKillersAttached then
        return
    end
    frame.ShieldFramesAbsorbKillersAttached = true

    -- Never OnShow-detach totalAbsorb / overlay — that raced our snapshot and left
    -- frames with no hatch at all. Only suppress Blizzard's edge markers.
    if frame.overAbsorbGlow and frame.overAbsorbGlow.HookScript then
        frame.overAbsorbGlow:HookScript("OnShow", function(self)
            if IsEnabled() then
                HideBlizzOvershieldGlow(frame, self)
            end
        end)
    end
    for _, key in ipairs({ "TotalAbsorbLeftShadow", "totalAbsorbLeftShadow" }) do
        local shadow = frame[key]
        if shadow and shadow.HookScript then
            shadow:HookScript("OnShow", function(self)
                if not IsEnabled() then
                    return
                end
                if self.SetAlpha then
                    self:SetAlpha(0)
                end
                self:Hide()
            end)
        end
    end
end

local function IsOurShieldRegion(frame, region)
    if not frame or not region then
        return false
    end
    return region == frame.ShieldFramesOverlay
        or region == frame.ShieldFramesGlow
        or region == frame.ShieldFramesEdgeGlow
        or region == frame.ShieldFramesEdgeGlowSoft
        or region == frame.ShieldFramesTint
        or region == frame.ShieldFramesOverlayClip
        or region == frame.ShieldFramesOverlayBar
end

local function RegionIsShown(region)
    if not region or IsFrameForbidden(region) then
        return false
    end
    if not region.IsShown then
        return true
    end
    local ok, shown = pcall(region.IsShown, region)
    if not ok or IsSecret(shown) then
        return false
    end
    return shown == true
end

-- True left edge of the FULL absorb hatch (Barrier + PW:S, etc.).
-- Take the leftmost edge among absorb visuals. IMPORTANT: a hatch that covers the
-- whole bar has inset ≈ 0 — that must win over a shorter Barrier StatusBar/shadow
-- at ~60%. Older code skipped inset <= 1 and locked the glow to Barrier.
local function ResolveAbsorbGlowLeftInset(frame, healthBar)
    if type(frame) ~= "table" or not healthBar then
        return nil
    end

    local okBar, barLeft, barWidth, barRight = pcall(function()
        return healthBar:GetLeft(), SafeNumber(healthBar:GetWidth()), healthBar:GetRight()
    end)
    if not okBar or not barLeft or not IsPositiveFinite(barWidth) or barWidth <= 1 then
        return nil
    end

    local candidates = {
        frame.totalAbsorbOverlay,
        frame.totalAbsorbBarOverlay,
        frame.totalAbsorb and frame.totalAbsorb.overlay,
        frame.TotalAbsorbLeftShadow,
        frame.totalAbsorbLeftShadow,
        frame.totalAbsorb,
        frame.totalAbsorbBar,
        healthBar.totalAbsorbOverlay,
        healthBar.totalAbsorb,
    }

    for _, bar in ipairs({ frame.totalAbsorb, frame.totalAbsorbBar, healthBar.totalAbsorb }) do
        if bar and bar.GetStatusBarTexture then
            local okFill, fill = pcall(bar.GetStatusBarTexture, bar)
            if okFill and fill then
                candidates[#candidates + 1] = fill
            end
        end
    end

    local bestInset
    local bestWidth = 0
    for _, region in ipairs(candidates) do
        if RegionIsShown(region) then
            local ok, left, right, width = pcall(function()
                return region:GetLeft(), region:GetRight(), SafeNumber(region:GetWidth())
            end)
            if ok then
                -- Prefer the widest right-aligned absorb chunk (true total hatch width).
                if right and barRight and IsPositiveFinite(width) and width > 1 then
                    if math.abs(right - barRight) <= 3 then
                        if width > bestWidth then
                            bestWidth = width
                            bestInset = barWidth - width
                            if bestInset < 0 then
                                bestInset = 0
                            end
                        end
                    end
                end
                if left then
                    local inset = left - barLeft
                    -- Allow 0: full-bar hatch starts at the health bar's left edge.
                    if inset >= 0 and inset < barWidth - 0.5 then
                        local widthFromLeft = barWidth - inset
                        if widthFromLeft > bestWidth + 0.5 then
                            bestWidth = widthFromLeft
                            bestInset = inset
                        elseif not bestInset then
                            bestInset = inset
                            bestWidth = widthFromLeft
                        end
                    end
                end
            end
        end
    end

    if bestInset then
        frame.ShieldFramesBlizzAbsorbWidth = bestWidth
        return bestInset
    end
    return nil
end

local function FrameHasBlizzAbsorbHatch(frame, healthBar)
    return ResolveAbsorbGlowLeftInset(frame, healthBar) ~= nil
end

local function SnapshotWidestAbsorbWidth(frame, healthBar)
    ResolveAbsorbGlowLeftInset(frame, healthBar)
    return SafeNumber(frame and frame.ShieldFramesBlizzAbsorbWidth)
end

local function HideAllBlizzAbsorbChrome(frame, healthBar)
    if type(frame) ~= "table" then
        return
    end

    -- Soft-hide only. Detaching in OnShow caused a race where Blizzard never stayed
    -- visible long enough to measure, and our owned draw sometimes never ran.
    local function SoftHide(region)
        if not region or IsFrameForbidden(region) then
            return
        end
        if region.SetAlpha then
            pcall(region.SetAlpha, region, 0)
        end
        if region.Hide then
            pcall(region.Hide, region)
        end
    end

    for _, key in ipairs({
        "totalAbsorb",
        "totalAbsorbOverlay",
        "totalAbsorbBar",
        "totalAbsorbBarOverlay",
        "TotalAbsorbLeftShadow",
        "totalAbsorbLeftShadow",
        "TotalAbsorbRightShadow",
        "totalAbsorbRightShadow",
        "overAbsorbGlow",
    }) do
        local region = frame[key]
        SoftHide(region)
        if region and region.overlay then
            SoftHide(region.overlay)
        end
        if region and region.GetStatusBarTexture then
            local ok, fill = pcall(region.GetStatusBarTexture, region)
            if ok then
                SoftHide(fill)
            end
        end
    end

    if healthBar then
        SoftHide(healthBar.totalAbsorb)
        SoftHide(healthBar.totalAbsorbOverlay)
    end

    if frame.overAbsorbGlow then
        HideBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
    end

    frame.ShieldFramesBlizzAbsorbHidden = true
    AttachBlizzAbsorbKillers(frame)
end

local function SafeOverlayHeight(healthBar)
    if not healthBar then
        return OVERLAY_TILE_SIZE
    end

    local _, height = healthBar:GetSize()
    height = SafeNumber(height)
    if height and height > 0 then
        return math.floor(height + 0.5)
    end

    return OVERLAY_TILE_SIZE
end

-- Own hatch + glow completely. Size from the best available signal; never strip
-- Blizzard until we have a drawable width.
local function ApplyOwnedOvershieldVisual(frame, healthBar, unit)
    if not frame or not healthBar then
        return false
    end

    local settings = GetOverlaySettings()
    local tintColor = GetOverlayTintColor(settings)

    local _, maxHealth = GetUnitHealthValues(frame, unit)
    maxHealth = SafeNumber(maxHealth)
    if not IsPositiveFinite(maxHealth) then
        local ok, barMax = pcall(function()
            return SafeNumber(select(2, healthBar:GetMinMaxValues()))
        end)
        if ok then
            maxHealth = barMax
        end
    end
    if not IsPositiveFinite(maxHealth) and frame.ShieldFramesLastMaxHealth then
        maxHealth = SafeNumber(frame.ShieldFramesLastMaxHealth)
    end

    local snap = unit and GetAbsorbSnapshot(unit, maxHealth) or nil
    local absorb = snap and SafeNumber(snap.total) or nil
    local absorbIsLive = IsPositiveFinite(absorb) and absorb > 0
    if unit then
        local calcTotal = select(1, GetCalculatorAbsorbValues(unit))
        calcTotal = SafeNumber(calcTotal)
        if IsPositiveFinite(calcTotal) and (not absorb or calcTotal > absorb) then
            absorb = calcTotal
            absorbIsLive = true
        end
    end

    local hasKnownAura = snap and snap.hasKnown == true
    local auraDepleted = snap and snap.depleted == true
    local readableAbsorb = unit and UnitHasReadableAbsorb(unit)
    -- Live Blizzard hatch (shown regions) or width just cached from FillBar.
    local liveWidth = SnapshotWidestAbsorbWidth(frame, healthBar)
    local blizzWidth = SafeNumber(frame.ShieldFramesBlizzAbsorbWidth)
    local hasLiveBlizz = IsPositiveFinite(liveWidth) and liveWidth > 1
    local hasCachedBlizz = IsPositiveFinite(blizzWidth) and blizzWidth > 1
    local hasPositiveAbsorb = IsPositiveFinite(absorb) and absorb > 0
    local glowLive = FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame)

    -- Combat Blood DK: aura scan often misses while Blizzard tip glow + last absorb
    -- still prove a shield. Prefer last readable amount so we don't early-out.
    if not hasPositiveAbsorb and frame.ShieldFramesLastAbsorbAmount then
        local lastAbsorb = SafeNumber(frame.ShieldFramesLastAbsorbAmount)
        if IsPositiveFinite(lastAbsorb)
            and lastAbsorb > 0
            and (
                glowLive
                or HasRecentAbsorbEvent(frame)
                or (unit and UnitAffectingCombat(unit))
            )
        then
            absorb = lastAbsorb
            hasPositiveAbsorb = true
            absorbIsLive = false
        end
    end

    -- Shields gone: never keep drawing from SoftHide cache alone once auras/absorb are empty.
    -- Rewriting cache from displayWidth used to make priest self-shields stick forever.
    if auraDepleted and not hasLiveBlizz and not hasPositiveAbsorb and not glowLive then
        frame.ShieldFramesBlizzAbsorbWidth = nil
        frame.ShieldFramesLastOverlayWidth = nil
        return false
    end
    -- Player readableAbsorb is often nil (secret) during Midnight combat. Do not treat
    -- that as "no shield" while Blizzard overAbsorbGlow / last absorb still say otherwise.
    if unit and not hasKnownAura and not hasPositiveAbsorb and not hasLiveBlizz and not glowLive then
        if readableAbsorb == false or (IsPlayerUnitToken(unit) and readableAbsorb ~= true) then
            frame.ShieldFramesBlizzAbsorbWidth = nil
            frame.ShieldFramesLastOverlayWidth = nil
            return false
        end
        if not hasCachedBlizz then
            frame.ShieldFramesLastOverlayWidth = nil
            return false
        end
    end

    local hasBlizzSize = hasLiveBlizz or hasCachedBlizz

    if hasLiveBlizz and (not IsPositiveFinite(blizzWidth) or liveWidth > blizzWidth) then
        blizzWidth = liveWidth
        frame.ShieldFramesBlizzAbsorbWidth = liveWidth
        hasCachedBlizz = true
        hasBlizzSize = true
    end

    local ownedWidth = SafeRegionWidth(healthBar)
    if not IsPositiveFinite(ownedWidth) then
        ownedWidth = SafeNumber(frame.ShieldFramesCachedBarWidth)
    end
    if not IsPositiveFinite(ownedWidth) then
        -- Player/compact health bars sometimes secret their width; the parent
        -- health container or unit frame often still reports a readable size.
        local parent = healthBar.GetParent and healthBar:GetParent()
        ownedWidth = SafeRegionWidth(parent)
        if not IsPositiveFinite(ownedWidth) then
            ownedWidth = SafeRegionWidth(frame)
        end
    end
    if not IsPositiveFinite(ownedWidth) or ownedWidth <= 0 then
        return false
    end
    frame.ShieldFramesCachedBarWidth = ownedWidth

    -- Size from the widest LIVE signal. Blizzard's secret-sized absorb pixel width is
    -- the real-time truth when aura/calculator amounts are secret. A stale
    -- LastAbsorbAmount must NOT override a smaller live Blizz hatch (Blood Shield depleting).
    local displayWidth
    if hasBlizzSize and IsPositiveFinite(blizzWidth) and blizzWidth > 1 then
        displayWidth = blizzWidth
    end
    if hasPositiveAbsorb and IsPositiveFinite(maxHealth) and maxHealth > 0 then
        local fromAura = (absorb / maxHealth) * ownedWidth
        if absorbIsLive then
            if not IsPositiveFinite(displayWidth) or fromAura > displayWidth then
                displayWidth = fromAura
            end
        elseif not IsPositiveFinite(displayWidth) then
            displayWidth = fromAura
        end
    end
    -- Fraction estimate only when we lack an absolute absorb total and Blizz width.
    if not hasPositiveAbsorb and not IsPositiveFinite(displayWidth) then
        local fraction = snap and snap.fraction
        if IsPositiveFinite(fraction) then
            local fromFraction = fraction * ownedWidth
            if IsPositiveFinite(fromFraction) then
                displayWidth = fromFraction
            end
        end
    end
    -- Blizzard tip glow only (Blood Shield / secret Midnight): no aura points, no hatch
    -- width — still draw so we don't leave apply-failed with a naked overAbsorbGlow.
    if (not IsPositiveFinite(displayWidth) or displayWidth <= 0)
        and (FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame))
    then
        local estimated = unit and EstimateAbsorbFromOvershieldContext(frame, unit, healthBar, maxHealth)
        if IsPositiveFinite(estimated) and IsPositiveFinite(maxHealth) and maxHealth > 0 then
            displayWidth = (estimated / maxHealth) * ownedWidth
            absorb = estimated
            hasPositiveAbsorb = true
        else
            local bootstrap = SafeNumber(frame.ShieldFramesLastOverlayWidth)
            if not IsPositiveFinite(bootstrap) or bootstrap <= 1 then
                bootstrap = DEFAULT_BOOTSTRAP_OVERLAY_WIDTH
            end
            displayWidth = bootstrap
        end
    end
    -- Never fall back to LastOverlayWidth alone — that kept hatch+glow after shields expired.
    if not IsPositiveFinite(displayWidth) or displayWidth <= 0 then
        return false
    end
    if displayWidth > ownedWidth then
        displayWidth = ownedWidth
    end

    local bar, overlay, glow, clip = EnsureOvershieldBar(frame, healthBar)
    if not overlay or overlay:IsForbidden() or not clip or clip:IsForbidden() then
        return false
    end

    -- Draw ours first, then hide Blizzard — never the reverse.
    SetFrameClipOverflow(frame, healthBar, true)

    if bar and not IsFrameForbidden(bar) then
        bar:Hide()
    end
    if frame.ShieldFramesTint and not IsFrameForbidden(frame.ShieldFramesTint) then
        frame.ShieldFramesTint:Hide()
        frame.ShieldFramesTint:SetAlpha(0)
    end

    clip:SetParent(frame)
    clip:ClearAllPoints()
    clip:SetAllPoints(healthBar)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel((healthBar.GetFrameLevel and healthBar:GetFrameLevel() or 0) + 8)
    clip:Show()

    local leftInset = ownedWidth - displayWidth
    if leftInset < 0 then
        leftInset = 0
    end

    overlay:SetParent(clip)
    overlay:ClearAllPoints()
    overlay:SetDrawLayer("ARTWORK", 1)
    overlay:SetPoint("TOPLEFT", clip, "TOPLEFT", leftInset, 0)
    overlay:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    overlay:SetHorizTile(true)
    overlay:SetVertTile(true)
    local totalHeight = SafeOverlayHeight(healthBar)
    overlay:SetTexCoord(0, displayWidth / OVERLAY_TILE_SIZE, 0, totalHeight / OVERLAY_TILE_SIZE)
    overlay:SetBlendMode("BLEND")
    overlay:SetVertexColor(tintColor.r or 1, tintColor.g or 1, tintColor.b or 1, settings.overlayAlpha)
    overlay:Show()

    -- Soft glow: custom texture with a bright center and alpha falloff both ways.
    -- Blizzard Shield-Overshield reads as hard vertical slabs when stretched here.
    if settings.showGlow ~= false then
        if frame.ShieldFramesEdgeGlowSoft then
            frame.ShieldFramesEdgeGlowSoft:Hide()
        end
        if frame.ShieldFramesEdgeGlowStrips then
            for _, strip in ipairs(frame.ShieldFramesEdgeGlowStrips) do
                strip:Hide()
            end
        end

        if not frame.ShieldFramesGlowHolder then
            frame.ShieldFramesGlowHolder = CreateFrame("Frame", nil, frame)
        end
        local holder = frame.ShieldFramesGlowHolder
        local hbLevel = healthBar.GetFrameLevel and healthBar:GetFrameLevel() or 0
        local clipLevel = clip.GetFrameLevel and clip:GetFrameLevel() or (hbLevel + 8)
        holder:SetParent(frame)
        holder:ClearAllPoints()
        holder:SetAllPoints(healthBar)
        holder:SetFrameLevel(math.max(clipLevel + 10, hbLevel + 40))
        holder:EnableMouse(false)
        holder:Show()

        if not frame.ShieldFramesEdgeGlow then
            frame.ShieldFramesEdgeGlow = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        if not frame.ShieldFramesEdgeGlowSoft then
            frame.ShieldFramesEdgeGlowSoft = holder:CreateTexture(nil, "OVERLAY", nil, 6)
        end

        local edge = frame.ShieldFramesEdgeGlow
        local edgeAdd = frame.ShieldFramesEdgeGlowSoft
        local color = settings.glowColor
        local r, g, b = color.r or 0.45, color.g or 0.92, color.b or 1
        -- Honor settings glowOpacity (0–100 → 0–1). Do not floor this — that made the slider useless.
        local glowAlpha = settings.glowAlpha
        if glowAlpha == nil then
            glowAlpha = 0.6
        end
        -- Keep a readable seam glow even for small absorbs (Divine Aegis, etc.).
        -- Shrinking with displayWidth made tiny hatches lose the leading edge entirely.
        local glowWidth = 14
        if ownedWidth < glowWidth then
            glowWidth = math.max(6, math.floor(ownedWidth + 0.5))
        end
        local glowLeft = leftInset - (glowWidth * 0.5)
        if glowLeft < 0 then
            glowLeft = 0
        end
        if glowLeft + glowWidth > ownedWidth then
            glowLeft = math.max(0, ownedWidth - glowWidth)
        end

        local function PlaceSoftGlow(tex, blend, alpha)
            tex:SetParent(holder)
            tex:SetDrawLayer("OVERLAY", 7)
            tex:ClearAllPoints()
            tex:SetTexture("Interface\\AddOns\\ShieldFrames\\Media\\SoftEdgeGlow")
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetBlendMode(blend)
            tex:SetWidth(glowWidth)
            tex:SetPoint("TOPLEFT", holder, "TOPLEFT", glowLeft, 0)
            tex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", glowLeft, 0)
            tex:SetVertexColor(r, g, b, alpha)
            if alpha and alpha > 0.001 then
                tex:Show()
            else
                tex:Hide()
            end
        end

        -- BLEND: visible on white priest bars (ADD clamps to white and disappears).
        -- ADD: keeps the punchy look on colored mage bars.
        PlaceSoftGlow(edge, "BLEND", glowAlpha)
        PlaceSoftGlow(edgeAdd, "ADD", glowAlpha * 0.85)

        if glow and not (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
            glow:Hide()
        end
        frame.ShieldFramesLastGlowLeft = glowLeft
        frame.ShieldFramesLastGlowWidth = glowWidth
    else
        if frame.ShieldFramesEdgeGlow then
            frame.ShieldFramesEdgeGlow:Hide()
        end
        if frame.ShieldFramesEdgeGlowSoft then
            frame.ShieldFramesEdgeGlowSoft:Hide()
        end
        if frame.ShieldFramesEdgeGlowStrips then
            for _, strip in ipairs(frame.ShieldFramesEdgeGlowStrips) do
                strip:Hide()
            end
        end
        if frame.ShieldFramesGlowHolder and not IsFrameForbidden(frame.ShieldFramesGlowHolder) then
            frame.ShieldFramesGlowHolder:Hide()
        end
        if glow and not (type(glow.IsForbidden) == "function" and glow:IsForbidden()) then
            glow:Hide()
        end
    end

    HideAllBlizzAbsorbChrome(frame, healthBar)

    if IsPositiveFinite(maxHealth) then
        frame.ShieldFramesLastMaxHealth = maxHealth
    end
    -- Only cache absorb amounts from LIVE aura/calculator reads. Stale LastAbsorb
    -- was freezing the hatch while Blood Shield depleted under Midnight secrets.
    if absorbIsLive and IsPositiveFinite(absorb) then
        frame.ShieldFramesLastAbsorbAmount = absorb
    elseif IsPositiveFinite(displayWidth) and IsPositiveFinite(ownedWidth) and ownedWidth > 0
        and IsPositiveFinite(maxHealth) and maxHealth > 0
        and (hasBlizzSize or glowLive)
    then
        -- Derive a tracking amount from Blizzard's live pixel width so the next
        -- frame still has a proportional fallback if the FillBar snapshot misses.
        frame.ShieldFramesLastAbsorbAmount = (displayWidth / ownedWidth) * maxHealth
    end
    frame.ShieldFramesLastOverlayWidth = displayWidth
    -- Do not copy displayWidth back into BlizzAbsorbWidth — that kept expired shields
    -- alive after SoftHide with no live Blizzard absorb bar left.
    if hasLiveBlizz and IsPositiveFinite(liveWidth) then
        frame.ShieldFramesBlizzAbsorbWidth = liveWidth
    end
    frame.ShieldFramesLastApplyPath = "owned-hatch-glow"
    frame.ShieldFramesUsingBlizzHatch = nil
    return true
end

-- Legacy name used by hooks — route to owned visuals.
local function ApplyGlowOnBlizzHatch(frame, healthBar)
    local unit = frame.displayedUnit or frame.unit
    return ApplyOwnedOvershieldVisual(frame, healthBar, unit)
end

-- Blizzard sizes absorb with secret SetValue; we can't read the amount but we can
-- snapshot the laid-out pixel width before we detach those regions.
local function SnapshotBlizzAbsorbWidth(frame, healthBar)
    if type(frame) ~= "table" then
        return nil
    end

    -- Measure live regions this pass only. Do NOT grow-only merge with the old
    -- cache — that froze Blood Shield at peak width while it depleted.
    local liveBest = nil

    local candidates = {
        frame.totalAbsorbOverlay,
        frame.totalAbsorbBarOverlay,
        frame.totalAbsorb,
        frame.totalAbsorbBar,
        healthBar and healthBar.totalAbsorbOverlay,
        healthBar and healthBar.totalAbsorb,
    }

    for _, region in ipairs(candidates) do
        if region and not IsFrameForbidden(region) then
            local ok, width = pcall(function()
                return SafeNumber(region.GetWidth and region:GetWidth())
            end)
            if ok and IsPositiveFinite(width) and width > 1 then
                if not liveBest or width > liveBest then
                    liveBest = width
                end
            end
        end
    end

    if IsPositiveFinite(liveBest) then
        frame.ShieldFramesBlizzAbsorbWidth = liveBest
        return liveBest
    end
    return SafeNumber(frame.ShieldFramesBlizzAbsorbWidth)
end

local function DetachShieldTexturesUnder(root, ownerFrame, depth)
    if type(root) ~= "table" or (depth or 0) > 6 then
        return
    end
    if IsFrameForbidden(root) then
        return
    end

    if root.GetRegions then
        local ok, regions = pcall(function()
            return { root:GetRegions() }
        end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if region and not IsOurShieldRegion(ownerFrame, region) and region.GetTexture then
                    local texOk, tex = pcall(region.GetTexture, region)
                    if texOk and type(tex) == "string" then
                        local lower = string.lower(tex)
                        if string.find(lower, "shield%-", 1, false)
                            or string.find(lower, "absorb", 1, false)
                        then
                            DetachBlizzAbsorbRegion(region)
                        end
                    end
                end
            end
        end
    end

    if root.GetChildren then
        local ok, children = pcall(function()
            return { root:GetChildren() }
        end)
        if ok and children then
            for _, child in ipairs(children) do
                if child and not IsOurShieldRegion(ownerFrame, child) then
                    DetachShieldTexturesUnder(child, ownerFrame, (depth or 0) + 1)
                end
            end
        end
    end
end

local function NukeBlizzAbsorbGeometry(frame)
    if type(frame) ~= "table" then
        return
    end

    -- Do not detach Blizzard's absorb hatch — it is the correctly sized shield visual.
    -- Only suppress the default right-edge overAbsorbGlow.
    if frame.overAbsorbGlow then
        HideBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
    end
end

local function HideCustomTextures(frame)
    HideOvershieldDisplay(frame)
end

local function GetTiledOverlayTexCoord(source, tileSize, totalHeight)
    tileSize = tileSize or OVERLAY_TILE_SIZE
    totalHeight = SafeNumber(totalHeight)
    if not totalHeight or totalHeight <= 0 then
        totalHeight = OVERLAY_TILE_SIZE
    else
        totalHeight = math.floor(totalHeight + 0.5)
    end

    if not source then
        return 0, 1, 0, totalHeight / tileSize
    end

    local width = source.GetWidth and source:GetWidth()
    if SafeNumber(width) and width > 0 then
        width = math.floor(width + 0.5)
        return 0, width / tileSize, 0, totalHeight / tileSize
    end

    return 0, 1, 0, totalHeight / tileSize
end

local function ApplyTiledOverlayTexture(overlay, fill, healthBar, tileSize)
    if not overlay then
        return
    end

    tileSize = tileSize or OVERLAY_TILE_SIZE
    overlay:SetHorizTile(true)
    overlay:SetVertTile(true)

    local totalHeight = SafeOverlayHeight(healthBar)
    local left, right, top, bottom = GetTiledOverlayTexCoord(overlay, tileSize, totalHeight)
    if left == 0 and right == 1 then
        left, right, top, bottom = GetTiledOverlayTexCoord(fill, tileSize, totalHeight)
    end
    if left == 0 and right == 1 then
        left, right, top, bottom = GetTiledOverlayTexCoord(healthBar, tileSize, totalHeight)
    end
    overlay:SetTexCoord(left, right, top, bottom)
end

local function ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, tileSize, fillAnchor, fillAnchorMode)
    if not overlay or IsFrameForbidden(overlay) then
        return false
    end

    if fillAnchor then
        -- Only stretch-anchor when the fill reports a finite positive width.
        local fillWidth = fillAnchor.GetWidth and SafeNumber(fillAnchor:GetWidth())
        if not IsPositiveFinite(fillWidth) then
            return false
        end
        overlayWidth = nil
    else
        overlayWidth = SafeNumber(overlayWidth)
        if not IsPositiveFinite(overlayWidth) then
            return false
        end
    end

    local parentFrame = GetOverlayParentFrame(frame, healthBar)
    local anchorFrame = GetOverlayAnchorFrame(frame, healthBar)
    local settings = GetOverlaySettings()
    tileSize = tileSize or overlay.tileSize or OVERLAY_TILE_SIZE
    local tintColor = GetOverlayTintColor(settings)
    local tint = frame and frame.ShieldFramesTint
    local anchorLeft = fillAnchorMode == "missingHealth" and "TOPRIGHT" or "TOPLEFT"
    local anchorLeftBottom = fillAnchorMode == "missingHealth" and "BOTTOMRIGHT" or "BOTTOMLEFT"

    if tint and not IsFrameForbidden(tint) then
        tint:SetParent(parentFrame)
        tint:ClearAllPoints()
        tint:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
        tint:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
        if fillAnchor then
            tint:SetPoint("TOPLEFT", fillAnchor, anchorLeft, 0, 0)
            tint:SetPoint("BOTTOMLEFT", fillAnchor, anchorLeftBottom, 0, 0)
        else
            tint:SetWidth(overlayWidth)
        end
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:SetVertexColor(
            tintColor.r or 1,
            tintColor.g or 1,
            tintColor.b or 1,
            settings.overlayAlpha
        )
        tint:Show()
    end

    overlay:SetParent(parentFrame)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    if fillAnchor then
        overlay:SetPoint("TOPLEFT", fillAnchor, anchorLeft, 0, 0)
        overlay:SetPoint("BOTTOMLEFT", fillAnchor, anchorLeftBottom, 0, 0)
        ApplyTiledOverlayTexture(overlay, fillAnchor, anchorFrame, tileSize)
    else
        overlay:SetWidth(overlayWidth)
        overlay:SetTexCoord(0, overlayWidth / tileSize, 0, OVERLAY_TILE_SIZE / tileSize)
    end
    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    overlay:SetBlendMode("BLEND")
    overlay:SetVertexColor(tintColor.r or 1, tintColor.g or 1, tintColor.b or 1, settings.overlayAlpha)
    overlay:Show()

    if glow and not IsFrameForbidden(glow) and settings.showGlow then
        glow:SetParent(parentFrame)
        local color = settings.glowColor
        glow:SetDrawLayer("OVERLAY", 7)
        glow:SetBlendMode("ADD")
        glow:ClearAllPoints()
        glow:SetWidth(GLOW_TEXTURE_WIDTH)
        glow:SetPoint("TOPRIGHT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetTexCoord(1, 0, 0, 1)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not IsFrameForbidden(glow) then
        glow:Hide()
    end

    return true
end

local function AnchorOverlayToFill(overlay, healthBar, fill, parent)
    overlay:SetParent(parent or healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
end

local function AnchorOverlayToHealthBarWidth(overlay, healthBar, overlayWidth, parent)
    overlayWidth = SafeNumber(overlayWidth)
    if not IsPositiveFinite(overlayWidth) then
        return false
    end
    overlay:SetParent(parent or healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetWidth(overlayWidth)
    return true
end

local function GetOwnedOverlayBarWidth(frame, healthBar)
    local bar = frame and frame.ShieldFramesOverlayBar
    if bar and not IsFrameForbidden(bar) then
        local width = SafeNumber(bar:GetWidth())
        if IsPositiveFinite(width) then
            frame.ShieldFramesCachedBarWidth = width
            return width
        end
    end

    local cached = frame and SafeNumber(frame.ShieldFramesCachedBarWidth)
    if IsPositiveFinite(cached) then
        return cached
    end

    -- Own clip is sized to the health bar; safe to measure (not Blizzard healthBar:GetWidth).
    local clip = frame and frame.ShieldFramesOverlayClip
    if clip and not IsFrameForbidden(clip) then
        local width = SafeNumber(clip:GetWidth())
        if IsPositiveFinite(width) then
            if frame then
                frame.ShieldFramesCachedBarWidth = width
            end
            return width
        end
    end

    return nil
end

local function ComputeAbsorbOverlayWidth(frame, healthBar, absorbAmount, maxHealth)
    absorbAmount = SafeNumber(absorbAmount)
    maxHealth = SafeNumber(maxHealth)
    if not absorbAmount or not maxHealth or maxHealth <= 0 or absorbAmount <= 0 then
        return nil
    end

    local barWidth = GetOwnedOverlayBarWidth(frame, healthBar)
    if not IsPositiveFinite(barWidth) then
        return nil
    end

    local width = (absorbAmount / maxHealth) * barWidth
    if not IsPositiveFinite(width) then
        return nil
    end
    -- Never let a bad ratio exceed the owned bar (stops screen-wide overlays).
    if width > barWidth then
        width = barWidth
    end
    return width
end

local function AnchorOvershieldClip(clip, healthBar, healthFill, overshieldAmount, unit, frame)
    -- Always clip to the health bar bounds so nothing (Blizz fill leftovers, glow)
    -- can paint past the frame edge.
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    clip:Show()
end

local function ApplyTiledStatusBarFill(fill, healthBar, tileSize)
    if not fill then
        return
    end

    tileSize = tileSize or OVERLAY_TILE_SIZE
    if fill.SetHorizTile then
        fill:SetHorizTile(true)
    end
    if fill.SetVertTile then
        fill:SetVertTile(true)
    end

    local totalHeight = SafeOverlayHeight(healthBar)
    local left, right, top, bottom = GetTiledOverlayTexCoord(fill, tileSize, totalHeight)
    if left == 0 and right == 1 then
        left, right, top, bottom = GetTiledOverlayTexCoord(healthBar, tileSize, totalHeight)
    end
    if fill.SetTexCoord then
        fill:SetTexCoord(left, right, top, bottom)
    end
end

local function ApplyStripePatternOverlay(frame, healthBar, fill, parent, settings, absorbAmount, maxHealth)
    -- Hatch lives on the absorb StatusBar fill so its width always matches SetValue.
    -- A separate full-frame texture + SetWidth was desyncing and flooding the bar.
    if not fill or (fill.IsForbidden and fill:IsForbidden()) then
        return nil
    end

    if frame and frame.ShieldFramesTint and not IsFrameForbidden(frame.ShieldFramesTint) then
        frame.ShieldFramesTint:Hide()
    end
    if frame and frame.ShieldFramesOverlay and not IsFrameForbidden(frame.ShieldFramesOverlay) then
        frame.ShieldFramesOverlay:Hide()
    end

    local tint = GetOverlayTintColor(settings)
    if fill.SetTexture then
        fill:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    end
    if fill.SetHorizTile then
        fill:SetHorizTile(true)
    end
    if fill.SetVertTile then
        fill:SetVertTile(true)
    end
    if fill.SetBlendMode then
        fill:SetBlendMode("BLEND")
    end
    if fill.SetVertexColor then
        fill:SetVertexColor(tint.r or 1, tint.g or 1, tint.b or 1, 1)
    end
    ApplyTiledStatusBarFill(fill, healthBar, OVERLAY_TILE_SIZE)

    local sizingAbsorb = SafeNumber(absorbAmount)
    if not IsPositiveFinite(sizingAbsorb) and frame and frame.ShieldFramesLastAbsorbAmount then
        sizingAbsorb = SafeNumber(frame.ShieldFramesLastAbsorbAmount)
    end
    local sizingMax = SafeNumber(maxHealth)
    if not IsPositiveFinite(sizingMax) and frame and frame.ShieldFramesLastMaxHealth then
        sizingMax = SafeNumber(frame.ShieldFramesLastMaxHealth)
    end

    -- Prefer the laid-out fill width (authoritative for reverse-fill SetValue).
    local displayWidth = SafeNumber(fill.GetWidth and fill:GetWidth())
    if not IsPositiveFinite(displayWidth) then
        displayWidth = ComputeAbsorbOverlayWidth(frame, healthBar, sizingAbsorb, sizingMax)
    end
    local barWidth = GetOwnedOverlayBarWidth(frame, healthBar)
    if IsPositiveFinite(displayWidth) and IsPositiveFinite(barWidth) and displayWidth > barWidth then
        displayWidth = barWidth
    end
    if not IsPositiveFinite(displayWidth) then
        displayWidth = SafeNumber(frame and frame.ShieldFramesLastOverlayWidth)
    end
    if not IsPositiveFinite(displayWidth) then
        return nil
    end

    if frame then
        frame.ShieldFramesLastOverlayWidth = displayWidth
    end
    return displayWidth
end

local function ApplyOvershieldBar(frame, healthBar, absorbAmount, maxHealth, overshieldAmount)
    local unit = frame.displayedUnit or frame.unit
    if ApplyOwnedOvershieldVisual(frame, healthBar, unit) then
        return true
    end

    local bar, overlay, glow, clip = EnsureOvershieldBar(frame, healthBar)
    if not overlay or overlay:IsForbidden() or not clip or clip:IsForbidden() then
        return false
    end

    AttachBlizzAbsorbKillers(frame)

    local settings = GetOverlaySettings()
    local tintColor = GetOverlayTintColor(settings)
    local unit = frame.unit or frame.displayedUnit

    -- Capture Blizzard's laid-out absorb width BEFORE we detach it. Midnight can size
    -- Shield-Overlay with secret absorb values we can't read — that wider hatch is
    -- what made our glow look short of the "real" shield.
    local blizzAbsorbWidth = SnapshotBlizzAbsorbWidth(frame, healthBar)

    local barAbsorb = absorbAmount
    if not CanAccessValue(barAbsorb) and frame.ShieldFramesLastAbsorbAmount and frame.ShieldFramesLastAbsorbAmount > 0 then
        barAbsorb = frame.ShieldFramesLastAbsorbAmount
    end
    local barMax = maxHealth
    if not CanAccessValue(barMax) then
        if frame.ShieldFramesLastMaxHealth and frame.ShieldFramesLastMaxHealth > 0 then
            barMax = frame.ShieldFramesLastMaxHealth
        else
            local _, fallbackMax = GetUnitHealthValues(frame, unit)
            if fallbackMax and CanAccessValue(fallbackMax) then
                barMax = fallbackMax
            end
        end
    end

    barAbsorb = SafeNumber(barAbsorb)
    barMax = SafeNumber(barMax)

    -- Clip parented to the unit frame, sized to the health bar — never a StatusBar child.
    clip:SetParent(frame)
    clip:ClearAllPoints()
    clip:SetAllPoints(healthBar)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel((healthBar.GetFrameLevel and healthBar:GetFrameLevel() or 0) + 8)
    clip:Show()

    -- Clip the compact frame (not the StatusBar) so Blizzard Shield-Fill can't bleed past the border.
    SetFrameClipOverflow(frame, healthBar, true)

    -- Legacy status-bar path stays hidden — one texture hatch only.
    if bar and not IsFrameForbidden(bar) then
        bar:Hide()
    end
    if frame.ShieldFramesTint and not IsFrameForbidden(frame.ShieldFramesTint) then
        frame.ShieldFramesTint:Hide()
    end

    local ownedWidth = SafeNumber(clip:GetWidth())
    if not IsPositiveFinite(ownedWidth) then
        ownedWidth = SafeNumber(healthBar and healthBar.GetWidth and healthBar:GetWidth())
    end
    if not IsPositiveFinite(ownedWidth) then
        ownedWidth = SafeNumber(frame.ShieldFramesCachedBarWidth)
    end
    if IsPositiveFinite(ownedWidth) then
        frame.ShieldFramesCachedBarWidth = ownedWidth
    end
    if not IsPositiveFinite(ownedWidth) or ownedWidth <= 0 then
        return false
    end

    local displayWidth
    if IsPositiveFinite(barAbsorb) and IsPositiveFinite(barMax) then
        displayWidth = (barAbsorb / barMax) * ownedWidth
    end
    -- Prefer Blizzard's pixel width when it's larger (secret absorb sized correctly in UI).
    if IsPositiveFinite(blizzAbsorbWidth) then
        if not IsPositiveFinite(displayWidth) or blizzAbsorbWidth > displayWidth then
            displayWidth = blizzAbsorbWidth
        end
        if displayWidth > ownedWidth then
            displayWidth = ownedWidth
        end
    end
    if not IsPositiveFinite(displayWidth) or displayWidth <= 0 then
        return false
    end
    if displayWidth > ownedWidth then
        displayWidth = ownedWidth
    end

    -- One hatch layer only; hide any leftover tint from older bootstrap paths.
    if frame.ShieldFramesTint and not IsFrameForbidden(frame.ShieldFramesTint) then
        frame.ShieldFramesTint:Hide()
        frame.ShieldFramesTint:SetAlpha(0)
    end

    -- Health fills left→right. Overshield hatch builds from the right. Glow marks
    -- the hatch's leftmost edge. Anytime we draw a hatch, show the glow.
    local canShowGlow = settings.showGlow ~= false and IsPositiveFinite(displayWidth)

    local leftInset = ownedWidth - displayWidth
    if leftInset < 0 then
        leftInset = 0
    end

    overlay:SetParent(clip)
    overlay:ClearAllPoints()
    overlay:SetDrawLayer("ARTWORK", 1)
    overlay:SetPoint("TOPLEFT", clip, "TOPLEFT", leftInset, 0)
    overlay:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    overlay:SetHorizTile(true)
    overlay:SetVertTile(true)
    local totalHeight = SafeOverlayHeight(healthBar)
    overlay:SetTexCoord(0, displayWidth / OVERLAY_TILE_SIZE, 0, totalHeight / OVERLAY_TILE_SIZE)
    overlay:SetBlendMode("BLEND")
    overlay:SetVertexColor(tintColor.r or 1, tintColor.g or 1, tintColor.b or 1, settings.overlayAlpha)
    overlay:Show()

    if glow and not glow:IsForbidden() and canShowGlow then
        local color = settings.glowColor
        local glowAlpha = settings.glowAlpha or 0.6
        -- Crisp edge marker at the exact hatch boundary (avoids Shield-Overshield inset).
        local glowWidth = 4
        glow:SetParent(clip)
        glow:SetDrawLayer("ARTWORK", 3)
        glow:ClearAllPoints()
        glow:SetWidth(glowWidth)
        glow:SetPoint("TOPLEFT", clip, "TOPLEFT", leftInset - (glowWidth * 0.5), 0)
        glow:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", leftInset - (glowWidth * 0.5), 0)
        glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        glow:SetTexCoord(0, 1, 0, 1)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, glowAlpha or 0.6)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    NukeBlizzAbsorbGeometry(frame)
    SuppressAllBlizzAbsorbVisuals(frame, healthBar)

    frame.ShieldFramesLastMaxHealth = barMax
    frame.ShieldFramesLastOverlayWidth = displayWidth
    frame.ShieldFramesLastApplyPath = "texture-clip"
    return true
end

local MIDNIGHT_UNIT_FRAME_UNITS = {
    player = true,
    target = true,
    focus = true,
}

local function IsMidnightUnitFrame(frame)
    return frame and frame.unit and MIDNIGHT_UNIT_FRAME_UNITS[frame.unit] == true
end

local function ClearUnsupportedUnitFrame(frame)
    if not frame then
        return
    end
    if frame.ShieldFramesOvershieldActive or frame.ShieldFramesOverlay or frame.ShieldFramesOverlayBar then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
    end
end

local function SafeHealthBarWidth(frame)
    if not frame then
        return nil
    end
    return SafeNumber(frame.ShieldFramesCachedBarWidth)
end

local function ComputeBootstrapOverlayWidth(frame, healthBar, unit, maxHealth)
    -- Prefer Blood Shield / known absorb proportion when we have amounts but
    -- ApplyOwned earlier failed (usually secret bar width — now recovered via
    -- SafeRegionWidth). Avoid a sticky fixed 48px tip.
    local ownedWidth = SafeRegionWidth(healthBar)
        or SafeNumber(frame and frame.ShieldFramesCachedBarWidth)
    local maxH = SafeNumber(maxHealth) or SafeNumber(frame and frame.ShieldFramesLastMaxHealth)
    if unit and IsPositiveFinite(ownedWidth) and IsPositiveFinite(maxH) then
        local snap = GetAbsorbSnapshot(unit, maxH)
        local absorb = snap and SafeNumber(snap.total)
        if not IsPositiveFinite(absorb) then
            absorb = SafeNumber(frame and frame.ShieldFramesLastAbsorbAmount)
        end
        if IsPositiveFinite(absorb) and absorb > 0 then
            local width = (absorb / maxH) * ownedWidth
            if IsPositiveFinite(width) and width > 0 then
                if width > ownedWidth then
                    width = ownedWidth
                end
                return width
            end
        elseif snap and IsPositiveFinite(snap.fraction) then
            local width = snap.fraction * ownedWidth
            if IsPositiveFinite(width) and width > 0 then
                return math.min(width, ownedWidth)
            end
        end
    end

    local cached = frame and SafeNumber(frame.ShieldFramesLastOverlayWidth)
    if cached and cached > 0 then
        return cached
    end
    return DEFAULT_BOOTSTRAP_OVERLAY_WIDTH
end

local function GetHealthBarFill(healthBar)
    if not healthBar or IsFrameForbidden(healthBar) then
        return nil
    end

    local ok, fill = pcall(function()
        return healthBar:GetStatusBarTexture()
    end)
    if not ok or not fill or IsFrameForbidden(fill) then
        return nil
    end

    return fill
end

local function CanUseFillAnchor(frame, unit)
    local curHealth, maxHealth = GetUnitHealthValues(frame, unit)
    if curHealth and maxHealth and CanAccessValue(curHealth) and CanAccessValue(maxHealth) then
        return curHealth < maxHealth
    end
    return false
end

local function ApplyOvershieldBootstrapOverlay(frame, healthBar, maxHealth, overshieldAmount, unit)
    if frame.ShieldFramesOverlayBar and not IsFrameForbidden(frame.ShieldFramesOverlayBar) then
        frame.ShieldFramesOverlayBar:Hide()
    end
    if frame.ShieldFramesOverlayClip and not IsFrameForbidden(frame.ShieldFramesOverlayClip) then
        frame.ShieldFramesOverlayClip:Hide()
    end

    local overlay, glow = EnsureCustomTextures(frame, healthBar)
    local healthFill = GetHealthBarFill(healthBar)

    if FrameHasBlizzOvershieldGlow(frame) then
        frame.ShieldFramesLastBootstrapMode = "glow-width"
        local overlayWidth = ComputeBootstrapOverlayWidth(frame, healthBar, unit, maxHealth)
        if ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, 32) then
            frame.ShieldFramesLastOverlayWidth = overlayWidth
            -- Do not poison CachedBarWidth with the stripe pixel width (was 48).
            return true
        end
    end

    if healthFill and CanUseFillAnchor(frame, unit) then
        frame.ShieldFramesLastBootstrapMode = "fill-anchor"
        if ApplyOverlayAndGlow(frame, healthBar, overlay, glow, nil, 32, healthFill, "missingHealth") then
            frame.ShieldFramesLastOverlayWidth = nil
            return true
        end
    end

    frame.ShieldFramesLastBootstrapMode = nil
    return false
end

local function CanRenderAbsorbOnStatusBar(renderAbsorb)
    return renderAbsorb ~= nil and (CanAccessValue(renderAbsorb) or IsSecret(renderAbsorb))
end

local function CanRenderMaxOnStatusBar(maxHealth)
    return maxHealth ~= nil and (CanAccessValue(maxHealth) or IsSecret(maxHealth))
end

local function ApplyMidnightOvershieldDisplay(frame, healthBar, renderAbsorb, renderMaxHealth, overshieldAmount, unit)
    -- Primary path: glow on Blizzard's live absorb hatch (correct secret width).
    if ApplyGlowOnBlizzHatch(frame, healthBar) then
        return true
    end

    local inCombat = unit and UnitAffectingCombat(unit)
    -- Prefer last readable absorb over a secret calculator value so combat sizing can update.
    local displayAbsorb = renderAbsorb
    if (not displayAbsorb or not CanAccessValue(displayAbsorb))
        and frame.ShieldFramesLastAbsorbAmount
        and frame.ShieldFramesLastAbsorbAmount > 0
        and (
            inCombat
            or KnownAbsorbAuraEvidenceActive(frame, unit)
            or FrameHasBlizzOvershieldGlow(frame)
            or HasRecentAbsorbEvent(frame)
        )
    then
        displayAbsorb = frame.ShieldFramesLastAbsorbAmount
    end

    local max = renderMaxHealth
    if not CanAccessValue(max) then
        if frame.ShieldFramesLastMaxHealth and frame.ShieldFramesLastMaxHealth > 0 then
            max = frame.ShieldFramesLastMaxHealth
        else
            local _, fallbackMax = GetUnitHealthValues(frame, unit)
            if CanAccessValue(fallbackMax) then
                max = fallbackMax
            end
        end
    end

    -- Status bar only with finite readable absorb+max. Secret SetValue/SetMinMaxValues
    -- produced NaN fill widths that stretch-anchored across the screen (group combat).
    local absorbForBar = CanAccessValue(displayAbsorb) and displayAbsorb
        or (CanAccessValue(renderAbsorb) and renderAbsorb)
        or nil
    absorbForBar = SafeNumber(absorbForBar)
    max = SafeNumber(max)
    if IsPositiveFinite(absorbForBar) and IsPositiveFinite(max) then
        if ApplyOvershieldBar(frame, healthBar, absorbForBar, max, overshieldAmount) then
            return true
        end
    end

    -- Secret absolute absorb/max: size from known absorb auras as a fraction of bar width
    -- (PW:S / barriers on party frames where UnitHealthMax / UnitGetTotalAbsorbs are secret).
    local fraction = unit and EstimateKnownAbsorbBarFraction(unit)
    if IsPositiveFinite(fraction) then
        if ApplyOvershieldBar(frame, healthBar, fraction, 1, overshieldAmount) then
            frame.ShieldFramesLastApplyPath = "texture-clip-fraction"
            return true
        end
    end

    -- Last resort: Blizzard already laid out the absorb bar with secret values.
    -- Snapshot that pixel width and redraw our hatch+glow to match.
    if ApplyOvershieldBar(frame, healthBar, nil, nil, overshieldAmount) then
        frame.ShieldFramesLastApplyPath = "texture-clip-blizz-width"
        return true
    end

    local glowLive = FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame)
    if not inCombat then
        -- Out of combat: only bootstrap when Blizzard still shows a live overshield glow.
        if not glowLive then
            frame.ShieldFramesLastApplyPath = "skipped-ooc"
            return false
        end
    end

    -- Secret absorb + Blizzard tip glow only (Blood Shield under Midnight): owned hatch
    -- with health-fraction / bootstrap width. Do not leave apply-failed with no overlay.
    if glowLive then
        if ApplyOwnedOvershieldVisual(frame, healthBar, unit) then
            frame.ShieldFramesLastApplyPath = "owned-glow-bootstrap"
            return true
        end
        if ApplyOvershieldBootstrapOverlay(frame, healthBar, max, overshieldAmount, unit) then
            frame.ShieldFramesLastApplyPath = "bootstrap"
            return true
        end
    end

    frame.ShieldFramesLastApplyPath = "skipped-no-readable-absorb"
    return false
end

local function ShouldKeepPreviousOverlay(frame, unit, totalAbsorb, overshieldAmount, absorbAmount)
    if HasClearNoAbsorbSignal(frame, unit, totalAbsorb, overshieldAmount) then
        return false
    end

    if absorbAmount ~= nil and CanAccessValue(absorbAmount) and absorbAmount <= 0 then
        return false
    end

    if unit and KnownAbsorbAuraIsDepleted(unit) then
        return false
    end

    return frame.ShieldFramesOvershieldActive
        and FrameShowsCustomOverlay(frame)
        and HasActiveAbsorbEvidence(frame, unit, totalAbsorb, overshieldAmount)
end

local function UpdateMidnightOvershield(frame, healthBar, unit)
    if not frame then
        return
    end
    if frame.ShieldFramesUpdateLock then
        frame.ShieldFramesLastUpdateSkipReason = "locked"
        return
    end
    frame.ShieldFramesUpdateLock = true
    frame.ShieldFramesLastUpdateSkipReason = nil
    frame.ShieldFramesLastUpdateError = nil

    local ok, err = pcall(function()
    RefreshKnownAbsorbAuraState(frame, unit)

    -- Own hatch+glow when Blizzard shows absorb OR we know absorb auras are up.
    -- Do this before clear/evidence checks (party absorb amounts are often secret).
    -- Also when only overAbsorbGlow is live — Blood Shield aura can be fully secret.
    local unitToken = unit or frame.displayedUnit or frame.unit
    local absorbSnap = unitToken and GetAbsorbSnapshot(unitToken, nil) or nil
    local cachedBlizz = SafeNumber(frame.ShieldFramesBlizzAbsorbWidth)
    local glowLive = FrameHasBlizzOvershieldGlow(frame) or FrameHasRawOvershieldGlow(frame)
    if FrameHasBlizzAbsorbHatch(frame, healthBar)
        or (absorbSnap and absorbSnap.hasKnown)
        or (IsPositiveFinite(cachedBlizz) and cachedBlizz > 1)
        or glowLive
    then
        if ApplyOwnedOvershieldVisual(frame, healthBar, unitToken) then
            SetFrameOvershieldActive(frame, true)
            frame.ShieldFramesLastApplyResult = true
            frame.ShieldFramesLastUpdateSkipReason = nil
            return
        end
    end

    local blizzGlow = frame.overAbsorbGlow
    local totalAbsorb, overshieldAmount, maxHealth = GetCalculatorAbsorbValues(unit)

    if HasClearNoAbsorbSignal(frame, unit, totalAbsorb, overshieldAmount) then
        ClearFrameOvershieldState(frame)
        frame.ShieldFramesLastUpdateSkipReason = "clear-no-absorb"
        return
    end

    if not MidnightFrameHasAbsorb(frame, overshieldAmount, totalAbsorb, unit) then
        -- Only keep owned hatch if Apply still has live aura/Blizz evidence.
        if ApplyOwnedOvershieldVisual(frame, healthBar, unit) then
            SetFrameOvershieldActive(frame, true)
            frame.ShieldFramesLastApplyResult = true
            frame.ShieldFramesLastUpdateSkipReason = "evidence-overridden-by-owned"
            return
        end
        ClearFrameOvershieldState(frame)
        frame.ShieldFramesLastUpdateSkipReason = "no-midnight-absorb"
        return
    end

    frame.ShieldFramesPendingAbsorbEstimate = nil
    local absorbAmount, renderMaxHealth, secretAbsorb = ResolveMidnightRenderValues(frame, unit, totalAbsorb, maxHealth, healthBar)
    local renderAbsorb = PickMidnightRenderAbsorb(absorbAmount, secretAbsorb)
    local hasRenderAbsorb = HasMidnightRenderAbsorb(absorbAmount, secretAbsorb)
    local hasVisualSignal = FrameHasOvershieldVisualSignal(frame)

    if not hasRenderAbsorb and not hasVisualSignal then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
        frame.ShieldFramesLastApplyResult = false
        frame.ShieldFramesLastUpdateSkipReason = "no-render-absorb"
        return
    end

    if not CanRenderMaxOnStatusBar(renderMaxHealth) then
        local _, fallbackMax = GetUnitHealthValues(frame, unit)
        if CanRenderMaxOnStatusBar(fallbackMax) then
            renderMaxHealth = fallbackMax
        end
    end
    frame.ShieldFramesLastRenderMaxHealth = renderMaxHealth

    local absorbReadable = renderAbsorb ~= nil and CanAccessValue(renderAbsorb)
    if absorbReadable then
        if SafeLessOrEqual(renderAbsorb, 0) == true then
            SetFrameOvershieldActive(frame, false)
            HideOvershieldDisplay(frame)
            frame.ShieldFramesLastApplyResult = false
            frame.ShieldFramesLastUpdateSkipReason = "readable-absorb-zero"
            return
        end
        if renderMaxHealth and CanAccessValue(renderMaxHealth) and SafeLessOrEqual(renderMaxHealth, 0) == true then
            SetFrameOvershieldActive(frame, false)
            HideOvershieldDisplay(frame)
            frame.ShieldFramesLastApplyResult = false
            frame.ShieldFramesLastUpdateSkipReason = "readable-max-health-zero"
            return
        end
        local readableMax = SafeNumber(renderMaxHealth)
        if IsPositiveFinite(readableMax) then
            frame.ShieldFramesLastMaxHealth = readableMax
        end
    elseif renderMaxHealth and CanAccessValue(renderMaxHealth) then
        local readableMax = SafeNumber(renderMaxHealth)
        if IsPositiveFinite(readableMax) then
            frame.ShieldFramesLastMaxHealth = readableMax
        end
    end

    SetFrameOvershieldActive(frame, true)
    local applied = ApplyMidnightOvershieldDisplay(
        frame,
        healthBar,
        renderAbsorb,
        renderMaxHealth,
        overshieldAmount,
        unit
    )

    if applied then
        if absorbReadable then
            frame.ShieldFramesLastAbsorbAmount = renderAbsorb
        elseif frame.ShieldFramesLastAbsorbAmount == nil then
            local fromAura = unit and GetAbsorbFromKnownAura(unit)
            if fromAura and fromAura > 0 then
                frame.ShieldFramesLastAbsorbAmount = fromAura
            end
        end
        GetOwnedOverlayBarWidth(frame, healthBar)
        SuppressAllBlizzAbsorbVisuals(frame, healthBar)
    else
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
        frame.ShieldFramesLastUpdateSkipReason = "apply-failed"
    end
    frame.ShieldFramesLastApplyResult = applied
    end)

    if not ok then
        frame.ShieldFramesLastUpdateError = err
        frame.ShieldFramesLastApplyResult = false
        frame.ShieldFramesLastUpdateSkipReason = "error"
        -- Partial apply before the error can leave a flooded hatch; clear it.
        HideOvershieldDisplay(frame)
        SetFrameOvershieldActive(frame, false)
    elseif frame.ShieldFramesLastApplyResult == nil then
        frame.ShieldFramesLastUpdateSkipReason = frame.ShieldFramesLastUpdateSkipReason or "early-exit"
    end

    frame.ShieldFramesUpdateLock = nil
end

local function UpdateCompactFrameInternal(frame)
    if not IsEnabled() or not frame then
        return
    end

    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return
    end

    if not frame.displayedUnit or not frame.healthBar then
        return
    end

    local healthBar = frame.healthBar
    local blizzGlow = frame.overAbsorbGlow

    if UsesHealPredictionCalculator() then
        UpdateMidnightOvershield(frame, healthBar, frame.displayedUnit)
        return
    end

    local overlay = frame.totalAbsorbOverlay
    local glow = blizzGlow
    local absorbBar = frame.totalAbsorb

    if not overlay or overlay:IsForbidden() then
        return
    end

    local curHealth = SafeNumber(healthBar:GetValue())
    local _, maxHealth = healthBar:GetMinMaxValues()
    maxHealth = SafeNumber(maxHealth)
    if not curHealth or not maxHealth or maxHealth <= 0 then
        return
    end

    local overshield = GetOvershieldAmount(frame.displayedUnit, curHealth, maxHealth)
    if overshield <= 0 then
        if glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    local barWidth = SafeNumber(healthBar:GetWidth())
    if not barWidth or barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
    if overlayWidth <= 0 then
        return
    end

    if absorbBar and not absorbBar:IsForbidden() and absorbBar:IsShown() then
        EnsureCustomTextures(frame, healthBar)
        local tint = frame.ShieldFramesTint
        local settings = GetOverlaySettings()
        local tintColor = GetOverlayTintColor(settings)
        local tileSize = overlay.tileSize or OVERLAY_TILE_SIZE
        local totalHeight = SafeOverlayHeight(healthBar)

        if tint and not tint:IsForbidden() then
            tint:SetParent(healthBar)
            tint:ClearAllPoints()
            tint:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
            tint:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
            tint:SetWidth(overlayWidth)
            tint:SetTexture("Interface\\Buttons\\WHITE8X8")
            tint:SetVertexColor(
                tintColor.r or 1,
                tintColor.g or 1,
                tintColor.b or 1,
                settings.overlayAlpha
            )
            tint:Show()
        end

        overlay:ClearAllPoints()
        overlay:SetParent(healthBar)
        overlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
        overlay:SetWidth(overlayWidth)
        overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
        overlay:SetBlendMode("BLEND")
        overlay:SetVertexColor(tintColor.r or 1, tintColor.g or 1, tintColor.b or 1, settings.overlayAlpha)
        overlay:Show()

        if glow and not glow:IsForbidden() and settings.showGlow then
            local color = settings.glowColor
            glow:SetDrawLayer("OVERLAY", 7)
            glow:SetBlendMode("ADD")
            glow:ClearAllPoints()
            glow:SetWidth(GLOW_TEXTURE_WIDTH)
            glow:SetPoint("TOPRIGHT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetTexCoord(1, 0, 0, 1)
            glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
            glow:Show()
        elseif glow and not glow:IsForbidden() then
            glow:Hide()
        end
        SuppressBlizzAbsorbOverlays(frame, healthBar)
        return
    end

    EnsureCustomTextures(frame, healthBar)
    if ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, overlay.tileSize) then
        SuppressBlizzAbsorbOverlays(frame, healthBar)
    end
end

function ns.UpdateCompactFrame(frame)
    SafeUpdateCompactFrame(frame)
end

local function UpdateUnitFrame(frame)
    if not IsEnabled() or not frame then
        return
    end

    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return
    end

    if not frame.unit then
        return
    end

    if UsesHealPredictionCalculator() and not IsMidnightUnitFrame(frame) then
        ClearUnsupportedUnitFrame(frame)
        return
    end

    local healthBar = frame.healthbar or frame.healthBar
    if not healthBar then
        return
    end

    if UsesHealPredictionCalculator() then
        UpdateMidnightOvershield(frame, healthBar, frame.unit)
        return
    end

    if IsFrameForbidden(healthBar) then
        return
    end

    local curHealth, maxHealth = GetUnitHealthValues(frame, frame.unit)
    if not curHealth or not maxHealth or maxHealth <= 0 then
        return
    end

    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
    totalAbsorb = SafeNumber(totalAbsorb) or 0
    if totalAbsorb <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local overshield = GetOvershieldAmount(frame.unit, curHealth, maxHealth)
    if overshield <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local barWidth = SafeNumber(healthBar:GetWidth())
    if not barWidth or barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
    if overlayWidth <= 0 then
        HideOvershieldDisplay(frame)
        return
    end

    local overlay, glow = EnsureCustomTextures(frame, healthBar)
    if ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, 32) then
        SuppressBlizzAbsorbOverlays(frame, healthBar)
    end

    if frame.overAbsorbGlow and not frame.overAbsorbGlow:IsForbidden() then
        HideBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
    end
end

local function SafeUpdateCompactFrame(frame)
    pcall(UpdateCompactFrameInternal, frame)
end

local function SafeUpdateUnitFrame(frame)
    pcall(UpdateUnitFrame, frame)
end

local pendingUnitFrameUpdates = {}
local pendingCompactFrameUpdates = {}

local function DeferUnitFrameUpdate(frame)
    if not frame then
        return
    end
    if not IsMidnightUnitFrame(frame) then
        ClearUnsupportedUnitFrame(frame)
        return
    end
    if pendingUnitFrameUpdates[frame] then
        return
    end
    pendingUnitFrameUpdates[frame] = true
    C_Timer.After(0, function()
        pendingUnitFrameUpdates[frame] = nil
        SafeUpdateUnitFrame(frame)
    end)
end

local function DeferCompactFrameUpdate(frame)
    if not frame then
        return
    end
    if pendingCompactFrameUpdates[frame] then
        return
    end
    pendingCompactFrameUpdates[frame] = true
    C_Timer.After(0, function()
        pendingCompactFrameUpdates[frame] = nil
        SafeUpdateCompactFrame(frame)
    end)
end

local function ForEachCompactFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    local function TryFrame(frame)
        -- flowFrames can contain layout tokens like "linebreak", not only frames.
        if type(frame) ~= "table" or type(callback) ~= "function" then
            return
        end
        if frame.IsForbidden and frame:IsForbidden() then
            return
        end
        callback(frame)
    end

    if CompactPartyFrame and CompactPartyFrame.members then
        for _, memberFrame in pairs(CompactPartyFrame.members) do
            TryFrame(memberFrame)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.flowFrames then
        for _, memberFrame in ipairs(CompactPartyFrame.flowFrames) do
            TryFrame(memberFrame)
        end
    end

    for index = 1, 5 do
        TryFrame(_G["CompactPartyFrameMember" .. index])
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.flowFrames then
        for _, memberFrame in ipairs(CompactRaidFrameContainer.flowFrames) do
            TryFrame(memberFrame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.groups then
        for _, group in pairs(CompactRaidFrameContainer.groups) do
            if group and group.flowFrames then
                for _, memberFrame in ipairs(group.flowFrames) do
                    TryFrame(memberFrame)
                end
            end
        end
    end

    for index = 1, 40 do
        TryFrame(_G["CompactRaidFrame" .. index])
    end
end

local function RefreshUnitFrameByUnit(unit)
    if not unit then
        return
    end

    if PlayerFrame and PlayerFrame.unit == unit then
        SafeUpdateUnitFrame(PlayerFrame)
    end
    if TargetFrame and TargetFrame.unit == unit then
        SafeUpdateUnitFrame(TargetFrame)
    end
    if FocusFrame and FocusFrame.unit == unit then
        SafeUpdateUnitFrame(FocusFrame)
    end
    if PetFrame and PetFrame.unit == unit then
        ClearUnsupportedUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(memberFrame)
        local u = memberFrame.displayedUnit or memberFrame.unit
        if u == unit or SafeUnitIsUnit(u, unit) then
            SafeUpdateCompactFrame(memberFrame)
        end
    end)
end

local function RestoreBlizzGlowFadeState(frame)
    if not frame then
        return
    end
    RestoreBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
end

function ns.RestoreAllBlizzGlowFadeStates()
    RestoreBlizzGlowFadeState(PlayerFrame)
    RestoreBlizzGlowFadeState(TargetFrame)
    RestoreBlizzGlowFadeState(FocusFrame)
    RestoreBlizzGlowFadeState(PetFrame)
    ForEachCompactFrame(RestoreBlizzGlowFadeState)
end

function ns.RefreshAllFrames()
    C_Timer.After(0, function()
        if not IsEnabled() then
            if PlayerFrame then
                RestoreBlizzAbsorbBars(PlayerFrame, PlayerFrame.healthbar or PlayerFrame.healthBar, true)
                RestoreBlizzOvershieldGlow(PlayerFrame, PlayerFrame.overAbsorbGlow)
                HideOvershieldDisplay(PlayerFrame)
            end
            if TargetFrame then
                RestoreBlizzAbsorbBars(TargetFrame, TargetFrame.healthbar or TargetFrame.healthBar, true)
                RestoreBlizzOvershieldGlow(TargetFrame, TargetFrame.overAbsorbGlow)
                HideOvershieldDisplay(TargetFrame)
            end
            if FocusFrame then
                RestoreBlizzAbsorbBars(FocusFrame, FocusFrame.healthbar or FocusFrame.healthBar, true)
                RestoreBlizzOvershieldGlow(FocusFrame, FocusFrame.overAbsorbGlow)
                HideOvershieldDisplay(FocusFrame)
            end
            ForEachCompactFrame(function(memberFrame)
                RestoreBlizzAbsorbBars(memberFrame, memberFrame.healthBar, true)
                RestoreBlizzOvershieldGlow(memberFrame, memberFrame.overAbsorbGlow)
                SetFrameClipOverflow(memberFrame, memberFrame.healthBar, false)
                HideOvershieldDisplay(memberFrame)
            end)
            return
        end

        if PlayerFrame then
            SafeUpdateUnitFrame(PlayerFrame)
        end
        if TargetFrame then
            SafeUpdateUnitFrame(TargetFrame)
        end
        if FocusFrame then
            SafeUpdateUnitFrame(FocusFrame)
        end
        if PetFrame then
            ClearUnsupportedUnitFrame(PetFrame)
        end

        ForEachCompactFrame(function(memberFrame)
            SafeUpdateCompactFrame(memberFrame)
        end)
    end)
end

local function ChatPrint(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        print(message)
    end
end

local function PrintDebugInfo()
    local ok, err = pcall(function()
        local unit = "player"

        local version = GetAddonMetadata("Version") or "?"
        ChatPrint("|cff00ccffShieldFrames|r v" .. version .. " debug")
        ChatPrint("|cff00ccffShieldFrames|r enabled: " .. tostring(IsEnabled()))
        ChatPrint("|cff00ccffShieldFrames|r in combat: " .. tostring(UnitAffectingCombat(unit)))
        ChatPrint("|cff00ccffShieldFrames|r midnight APIs: " .. tostring(UsesHealPredictionCalculator()))

        if UsesHealPredictionCalculator() then
            UpdateHealPredictionCalculator(unit)

            local playerFrame = PlayerFrame
            local playerHealthBar = playerFrame and (playerFrame.healthbar or playerFrame.healthBar)
            local totalAbsorb, overshieldAmount, maxHealth = GetCalculatorAbsorbValues(unit)
            local absorbAmount, renderMaxHealth, secretAbsorb
            if playerFrame and playerHealthBar then
                absorbAmount, renderMaxHealth, secretAbsorb = ResolveMidnightRenderValues(
                    playerFrame,
                    unit,
                    totalAbsorb,
                    maxHealth,
                    playerHealthBar
                )
            end
            local renderAbsorb = PickMidnightRenderAbsorb(absorbAmount, secretAbsorb)

            ChatPrint("|cff00ccffShieldFrames|r readable absorb: " .. tostring(UnitHasReadableAbsorb(unit)))
            ChatPrint("|cff00ccffShieldFrames|r absorb aura active: " .. tostring(UnitHasKnownAbsorbCandidate(unit)))
            ChatPrint("|cff00ccffShieldFrames|r learned absorb spells: " .. tostring(CountLearnedAbsorbSpellIds()))
            ChatPrint("|cff00ccffShieldFrames|r absorb aura depleted: " .. tostring(KnownAbsorbAuraIsDepleted(unit)))
            local bloodShield = SafeGetAuraBySpellID(unit, 77535)
            local umbilicus = SafeGetAuraBySpellID(unit, 391527) or SafeGetAuraBySpellID(unit, 193320)
            ChatPrint("|cff00ccffShieldFrames|r blood shield aura: " .. tostring(not not bloodShield))
            ChatPrint("|cff00ccffShieldFrames|r umbilicus eternus aura: " .. tostring(not not umbilicus))
            local blazingBarrier = SafeGetAuraBySpellID(unit, 235313)
            ChatPrint("|cff00ccffShieldFrames|r blazing barrier aura: " .. tostring(not not blazingBarrier))
            if playerFrame then
                ChatPrint("|cff00ccffShieldFrames|r recent absorb event: " .. tostring(HasRecentAbsorbEvent(playerFrame)))
                ChatPrint("|cff00ccffShieldFrames|r blizz glow faded by SF: " .. tostring(not not playerFrame.ShieldFramesBlizzGlowFaded))
            end
            ChatPrint("|cff00ccffShieldFrames|r player frame found: " .. tostring(not not playerFrame))
            if playerHealthBar then
                ChatPrint("|cff00ccffShieldFrames|r health bar forbidden: " .. tostring(IsFrameForbidden(playerHealthBar)))
            end
            if playerFrame then
                ChatPrint("|cff00ccffShieldFrames|r readable overshield: " .. tostring(UnitHasReadableOvershield(unit, playerFrame)))
            else
                ChatPrint("|cff00ccffShieldFrames|r readable overshield: unavailable (no player frame)")
            end
            ChatPrint("|cff00ccffShieldFrames|r blizz absorb bar visible: " .. tostring(
                playerFrame and FrameShowsAbsorbBar(playerFrame) or false
            ))
            if totalAbsorb ~= nil and CanAccessValue(totalAbsorb) then
                ChatPrint("|cff00ccffShieldFrames|r calculator total absorb: " .. tostring(totalAbsorb))
            else
                ChatPrint("|cff00ccffShieldFrames|r calculator total absorb: secret/unavailable")
            end
            if overshieldAmount ~= nil and CanAccessValue(overshieldAmount) then
                ChatPrint("|cff00ccffShieldFrames|r calculator overshield: " .. tostring(overshieldAmount))
            else
                ChatPrint("|cff00ccffShieldFrames|r calculator overshield: secret/unavailable")
            end
            if renderAbsorb ~= nil and CanAccessValue(renderAbsorb) then
                ChatPrint("|cff00ccffShieldFrames|r render absorb: " .. tostring(renderAbsorb))
            elseif secretAbsorb ~= nil then
                ChatPrint("|cff00ccffShieldFrames|r render absorb: secret (rendering)")
            else
                ChatPrint("|cff00ccffShieldFrames|r render absorb: secret/unavailable")
            end
            if renderMaxHealth ~= nil and CanAccessValue(renderMaxHealth) then
                ChatPrint("|cff00ccffShieldFrames|r render max health: " .. tostring(renderMaxHealth))
            else
                ChatPrint("|cff00ccffShieldFrames|r render max health: secret/unavailable")
            end

            local glowShown = playerFrame and FrameShowsOvershieldGlow(playerFrame)
            ChatPrint("|cff00ccffShieldFrames|r blizz overAbsorbGlow active: " .. tostring(glowShown))

            if playerFrame and playerHealthBar then
                local calcTotal, calcOvershield = GetCalculatorAbsorbValues(unit)
                ChatPrint("|cff00ccffShieldFrames|r midnight has absorb: " .. tostring(
                    MidnightFrameHasAbsorb(playerFrame, calcOvershield, calcTotal, unit)
                ))
                ChatPrint("|cff00ccffShieldFrames|r secret calculator absorb: " .. tostring(
                    HasSecretAbsorbValue(calcTotal, calcOvershield)
                ))
                ChatPrint("|cff00ccffShieldFrames|r overshield active flag: " .. tostring(
                    not not (playerFrame and playerFrame.ShieldFramesOvershieldActive)
                ))
                ChatPrint("|cff00ccffShieldFrames|r raw blizz glow shown: " .. tostring(
                    playerFrame and FrameHasRawOvershieldGlow(playerFrame) or false
                ))
                ChatPrint("|cff00ccffShieldFrames|r clear no absorb signal: " .. tostring(
                    HasClearNoAbsorbSignal(playerFrame, unit, calcTotal, calcOvershield)
                ))
            end

            if playerFrame then
                playerFrame.ShieldFramesUpdateLock = nil
                playerFrame.ShieldFramesLastApplyResult = nil
                playerFrame.ShieldFramesLastUpdateSkipReason = nil
                playerFrame.ShieldFramesLastUpdateError = nil
                local updateOk, updateErr = pcall(UpdateMidnightOvershield, playerFrame, playerHealthBar, unit)
                if not updateOk then
                    ChatPrint("|cff00ccffShieldFrames|r update error: " .. tostring(updateErr))
                end
                if playerFrame.ShieldFramesLastUpdateError then
                    ChatPrint("|cff00ccffShieldFrames|r update inner error: " .. tostring(playerFrame.ShieldFramesLastUpdateError))
                end
                if playerFrame.ShieldFramesLastUpdateSkipReason then
                    ChatPrint("|cff00ccffShieldFrames|r update skip reason: " .. tostring(playerFrame.ShieldFramesLastUpdateSkipReason))
                end
            end

            if playerFrame then
                if playerFrame.ShieldFramesLastApplyPath == "bootstrap" then
                    ChatPrint("|cff00ccffShieldFrames|r bootstrap mode: " .. tostring(playerFrame.ShieldFramesLastBootstrapMode or "none"))
                    if playerFrame.ShieldFramesLastBootstrapMode == "glow-width" or playerFrame.ShieldFramesLastBootstrapMode == "active-width" then
                        local bootstrapWidth = ComputeBootstrapOverlayWidth(
                            playerFrame,
                            playerHealthBar,
                            unit,
                            SafeNumber(playerFrame.ShieldFramesLastMaxHealth) or SafeNumber(renderMaxHealth)
                        )
                        ChatPrint("|cff00ccffShieldFrames|r bootstrap overlay width: " .. tostring(bootstrapWidth or "nil"))
                    end
                end
            end

            if playerFrame then
                ChatPrint("|cff00ccffShieldFrames|r last apply result: " .. tostring(playerFrame.ShieldFramesLastApplyResult))
                ChatPrint("|cff00ccffShieldFrames|r last apply path: " .. tostring(playerFrame.ShieldFramesLastApplyPath or "none"))
                local effectiveMax = playerFrame.ShieldFramesLastRenderMaxHealth
                if effectiveMax ~= nil and CanAccessValue(effectiveMax) then
                    ChatPrint("|cff00ccffShieldFrames|r effective max health: " .. tostring(effectiveMax))
                elseif effectiveMax ~= nil and IsSecret(effectiveMax) then
                    ChatPrint("|cff00ccffShieldFrames|r effective max health: secret (rendering)")
                else
                    ChatPrint("|cff00ccffShieldFrames|r effective max health: secret/unavailable")
                end
                ChatPrint("|cff00ccffShieldFrames|r cached absorb aura: " .. tostring(playerFrame.ShieldFramesKnownAbsorbAuraPresent))
            end

            local bar = playerFrame and playerFrame.ShieldFramesOverlayBar
            local barShown = bar and bar:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom overlay bar: " .. tostring(not not barShown))

            local texture = playerFrame and playerFrame.ShieldFramesOverlay
            local textureShown = texture and not IsFrameForbidden(texture) and texture:IsShown()
            if textureShown then
                ChatPrint("|cff00ccffShieldFrames|r custom overlay texture: true (clipped hatch)")
            else
                ChatPrint("|cff00ccffShieldFrames|r custom overlay texture: " .. tostring(not not textureShown))
            end

            local width = textureShown and SafeNumber(texture:GetWidth())
                or SafeNumber(playerFrame and playerFrame.ShieldFramesLastOverlayWidth)
            local barW = SafeNumber(playerFrame and playerFrame.ShieldFramesCachedBarWidth)
            if IsPositiveFinite(width) then
                ChatPrint("|cff00ccffShieldFrames|r overlay width: " .. tostring(math.floor(width + 0.5)))
            else
                ChatPrint("|cff00ccffShieldFrames|r overlay width: secret/unavailable")
            end
            if IsPositiveFinite(barW) then
                ChatPrint("|cff00ccffShieldFrames|r bar width: " .. tostring(math.floor(barW + 0.5)))
            end

            local blizzAbsorb = playerFrame and playerFrame.totalAbsorb
            local blizzAbsorbShown = blizzAbsorb and not IsFrameForbidden(blizzAbsorb) and blizzAbsorb:IsShown() and (not blizzAbsorb.GetAlpha or blizzAbsorb:GetAlpha() > 0.01)
            ChatPrint("|cff00ccffShieldFrames|r blizz totalAbsorb leaking: " .. tostring(not not blizzAbsorbShown))

            local edge = playerFrame and playerFrame.ShieldFramesEdgeGlow
            local glowActive = edge and edge.IsShown and edge:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom glow: " .. tostring(not not glowActive))
            if playerFrame and playerFrame.ShieldFramesLastGlowLeft then
                ChatPrint("|cff00ccffShieldFrames|r glow left/width: "
                    .. tostring(playerFrame.ShieldFramesLastGlowLeft)
                    .. " / "
                    .. tostring(playerFrame.ShieldFramesLastGlowWidth))
            end

            if not glowShown and not barShown and not textureShown
                and not (playerFrame and playerFrame.ShieldFramesOvershieldActive)
            then
                ChatPrint("|cff00ccffShieldFrames|r no overshield. Gain a shield absorb (Blood Shield, barrier, PW:S, etc.), then /sfdebug again.")
            end
            return
        end

        local absorb = SafeNumber(UnitGetTotalAbsorbs(unit)) or 0
        local health = SafeNumber(UnitHealth(unit))
        local maxHealth = SafeNumber(UnitHealthMax(unit))
        local overshield = GetOvershieldAmount(unit, health, maxHealth)

        ChatPrint("|cff00ccffShieldFrames|r player absorb: " .. tostring(absorb))
        if health and maxHealth then
            ChatPrint(string.format(
                "|cff00ccffShieldFrames|r overshield: %s  health: %s / %s",
                tostring(overshield or 0),
                tostring(health),
                tostring(maxHealth)
            ))
        else
            ChatPrint("|cff00ccffShieldFrames|r health values unavailable.")
        end
    end)

    if not ok then
        ChatPrint("|cffff0000ShieldFrames debug error:|r " .. tostring(err))
    end
end

local function OpenSettings()
    if Settings and Settings.OpenToCategory and ns.categoryID then
        Settings.OpenToCategory(ns.categoryID)
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(addonName)
        return
    end

    ChatPrint("|cff00ccffShieldFrames|r settings are not ready yet. Try again after login.")
end

local function ShieldFramesSlashHandler(msg)
    msg = strtrim(msg or "")
    local command = strlower(strsplit(" ", msg, 2) or "")

    if command == "debug" then
        PrintDebugInfo()
        return
    end

    if command == "help" then
        ChatPrint("|cff00ccffShieldFrames|r commands:")
        ChatPrint("  /shieldframes - open settings")
        ChatPrint("  /sfdebug or /shieldframes debug - print debug info to chat")
        return
    end

    if command == "" then
        OpenSettings()
        return
    end

    ChatPrint("|cff00ccffShieldFrames|r unknown command: " .. msg .. " (type /shieldframes help)")
end

SLASH_SHIELDFRAMES1 = "/shieldframes"
SLASH_SHIELDFRAMES2 = "/sf"
SlashCmdList["SHIELDFRAMES"] = ShieldFramesSlashHandler

SLASH_SHIELDFRAMESDEBUG1 = "/sfdebug"
SLASH_SHIELDFRAMESDEBUG2 = "/shieldframesdebug"
SlashCmdList["SHIELDFRAMESDEBUG"] = function()
    ChatPrint("|cff00ccffShieldFrames|r collecting debug info...")
    PrintDebugInfo()
end

-- Learn only from our own events, never from inside Blizzard FillBar/heal-prediction
-- hooks (that path taints and trips ADDON_ACTION_BLOCKED).
local pendingAbsorbLearnUnits = {}
local absorbLearnTicker
local pendingUnitRefresh = {}
local unitRefreshQueued

local function IsTrackedUnitToken(unit)
    if type(unit) ~= "string" then
        return false
    end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "pet" then
        return true
    end
    local prefix = unit:match("^(%a+)%d+$")
    return prefix == "party" or prefix == "raid"
end

local function QueueUnitFrameRefresh(unit)
    if not unit then
        return
    end
    pendingUnitRefresh[unit] = true
    if unitRefreshQueued then
        return
    end
    if not C_Timer or not C_Timer.After then
        local units = pendingUnitRefresh
        pendingUnitRefresh = {}
        for unitToken in pairs(units) do
            RefreshUnitFrameByUnit(unitToken)
        end
        return
    end
    unitRefreshQueued = true
    C_Timer.After(0, function()
        unitRefreshQueued = nil
        local units = pendingUnitRefresh
        pendingUnitRefresh = {}
        for unitToken in pairs(units) do
            RefreshUnitFrameByUnit(unitToken)
        end
    end)
end

local function QueueAbsorbSpellLearn(unit)
    if not unit then
        return
    end
    pendingAbsorbLearnUnits[unit] = true
    if absorbLearnTicker or not C_Timer or not C_Timer.After then
        return
    end
    absorbLearnTicker = true
    C_Timer.After(0, function()
        absorbLearnTicker = nil
        local units = pendingAbsorbLearnUnits
        pendingAbsorbLearnUnits = {}
        for unitToken in pairs(units) do
            pcall(TryLearnAbsorbSpellsFromUnit, unitToken)
        end
    end)
end

local function FrameNeedsSafetyPoll(frame)
    if not frame then
        return false
    end
    if frame.ShieldFramesOvershieldActive then
        return true
    end
    if FrameShowsCustomOverlay(frame) then
        return true
    end
    local blizzWidth = SafeNumber(frame.ShieldFramesBlizzAbsorbWidth)
    if IsPositiveFinite(blizzWidth) and blizzWidth > 1 then
        return true
    end
    return HasRecentAbsorbEvent(frame, 5)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        if event == "PLAYER_LOGIN" then
            GetLearnedAbsorbSpellIds()
            QueueAbsorbSpellLearn("player")
        end
        absorbSnapshots = {}
        ns.RefreshAllFrames()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" then
            InvalidateAbsorbSnapshot("player")
            local stillHasShield = UnitHasKnownAbsorbCandidate("player")
                or ((GetAbsorbFromKnownAura("player") or 0) > 0)
                or UnitHasReadableAbsorb("player") == true
                or (PlayerFrame and FrameHasRawOvershieldGlow(PlayerFrame))
            if stillHasShield then
                -- Soft leave: keep the overlay continuous so it doesn't jump when absorb becomes readable.
                if PlayerFrame then
                    PlayerFrame.ShieldFramesLastAbsorbEvent = nil
                    RefreshKnownAbsorbAuraState(PlayerFrame, "player")
                end
            else
                ClearFrameOvershieldState(PlayerFrame)
                ClearFrameOvershieldState(TargetFrame)
                ClearFrameOvershieldState(FocusFrame)
            end
        elseif PlayerFrame then
            PlayerFrame.ShieldFramesKnownAbsorbAuraPresent = nil
        end
        ns.RefreshAllFrames()
        return
    end

    -- Ignore nameplates / arena / boss tokens — absorb work is for player + group frames.
    if unit and not IsTrackedUnitToken(unit) then
        return
    end

    local function ClearPlayerOwnedOvershields()
        if PlayerFrame then
            ClearFrameOvershieldState(PlayerFrame)
        end
        ForEachCompactFrame(function(memberFrame)
            local u = memberFrame.displayedUnit or memberFrame.unit
            if IsPlayerUnitToken(u) then
                ClearFrameOvershieldState(memberFrame)
            end
        end)
    end

    if event == "UNIT_HEALTH" and unit then
        -- Health spam is frequent in combat; coalesce to next frame.
        QueueUnitFrameRefresh(unit)
        return
    end

    if event == "UNIT_ABSORB_AMOUNT_CHANGED" and unit then
        InvalidateAbsorbSnapshot(unit)
        QueueAbsorbSpellLearn(unit)
        local function TouchFrame(frame)
            if not frame then
                return
            end
            local healthBar = frame.healthbar or frame.healthBar
            SnapshotBlizzAbsorbWidth(frame, healthBar)
            local snap = GetAbsorbSnapshot(unit, nil)
            if (snap and snap.depleted) or UnitHasReadableAbsorb(unit) == false then
                frame.ShieldFramesLastAbsorbEvent = nil
            else
                frame.ShieldFramesLastAbsorbEvent = GetTime()
                if snap and snap.hasKnown then
                    frame.ShieldFramesKnownAbsorbAuraPresent = true
                end
                local _, maxHealth = GetUnitHealthValues(frame, unit)
                maxHealth = SafeNumber(maxHealth) or SafeNumber(frame.ShieldFramesLastMaxHealth)
                local totalKnown = GetTotalKnownAbsorbAmount(unit, maxHealth)
                if totalKnown and totalKnown > 0 then
                    frame.ShieldFramesLastAbsorbAmount = totalKnown
                else
                    -- Secret amounts: track from Blizzard's live hatch pixels so depleting
                    -- Blood Shield shrinks our overlay in real time.
                    local blizzW = SafeNumber(frame.ShieldFramesBlizzAbsorbWidth)
                    local barW = SafeRegionWidth(healthBar) or SafeNumber(frame.ShieldFramesCachedBarWidth)
                    if IsPositiveFinite(blizzW) and IsPositiveFinite(barW) and barW > 0
                        and IsPositiveFinite(maxHealth) and maxHealth > 0
                    then
                        frame.ShieldFramesLastAbsorbAmount = (blizzW / barW) * maxHealth
                    end
                end
            end
        end

        if unit == "player" and PlayerFrame then
            TouchFrame(PlayerFrame)
        end
        ForEachCompactFrame(function(memberFrame)
            local u = memberFrame.displayedUnit or memberFrame.unit
            if u and SafeUnitIsUnit(u, unit) then
                TouchFrame(memberFrame)
            end
        end)

        if unit == "player"
            and UnitHasReadableAbsorb(unit) == false
            and not UnitHasKnownAbsorbAura(unit)
        then
            ClearPlayerOwnedOvershields()
        end
    end

    if event == "UNIT_AURA" and unit then
        InvalidateAbsorbSnapshot(unit)
        QueueAbsorbSpellLearn(unit)
        if unit == "player"
            and not UnitHasKnownAbsorbAura(unit)
            and UnitHasReadableAbsorb(unit) == false
        then
            ClearPlayerOwnedOvershields()
        end
    end

    if event == "UNIT_MAXHEALTH" and unit then
        InvalidateAbsorbSnapshot(unit)
    end

    if unit then
        QueueUnitFrameRefresh(unit)
    else
        ns.RefreshAllFrames()
    end
end)

local function InitializeAddon()
    if ns.MigrateSavedSettings then
        ns.MigrateSavedSettings()
    else
        ns.MergeDefaults()
    end

    hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
        if not frame or not IsEnabled() then
            return
        end
        AttachBlizzAbsorbKillers(frame)
        -- Snapshot Blizzard's absorb width first (secret-sized), then coalesce the full update.
        SnapshotBlizzAbsorbWidth(frame, frame.healthBar)
        DeferCompactFrameUpdate(frame)
    end)

    hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
        if not frame or not IsEnabled() then
            return
        end
        local healthBar = frame.healthbar or frame.healthBar
        SnapshotBlizzAbsorbWidth(frame, healthBar)
        DeferUnitFrameUpdate(frame)
    end)

    if CompactUnitFrameUtil_UpdateFillBar then
        hooksecurefunc("CompactUnitFrameUtil_UpdateFillBar", function(frame, _, bar)
            if not frame or not IsEnabled() or not bar then
                return
            end
            if bar == frame.totalAbsorb or bar == frame.totalAbsorbOverlay then
                local ok, width = pcall(function()
                    return SafeNumber(bar.GetWidth and bar:GetWidth())
                end)
                local shown = true
                if bar.IsShown then
                    local okShown, isShown = pcall(bar.IsShown, bar)
                    shown = okShown and SafeBool(isShown)
                end
                if ok and IsPositiveFinite(width) and width > 1 then
                    -- Always accept live FillBar widths, including shrink on deplete.
                    frame.ShieldFramesBlizzAbsorbWidth = width
                elseif ok and shown and (not IsPositiveFinite(width) or width <= 1) then
                    -- Genuinely collapsed while Blizzard still owns a shown absorb bar.
                    frame.ShieldFramesBlizzAbsorbWidth = nil
                end
                -- Width snapshot only here; full hatch apply is coalesced with heal-pred updates.
                DeferCompactFrameUpdate(frame)
            end
        end)
    end

    -- Slow safety poll only for frames with recent absorb evidence (not a full raid sweep).
    C_Timer.NewTicker(1.0, function()
        if not IsEnabled() then
            return
        end
        if PlayerFrame and PlayerFrame.unit and FrameNeedsSafetyPoll(PlayerFrame) then
            SafeUpdateUnitFrame(PlayerFrame)
        end
        if TargetFrame and TargetFrame.unit and FrameNeedsSafetyPoll(TargetFrame) then
            SafeUpdateUnitFrame(TargetFrame)
        end
        if FocusFrame and FocusFrame.unit and FrameNeedsSafetyPoll(FocusFrame) then
            SafeUpdateUnitFrame(FocusFrame)
        end
        if PetFrame then
            ClearUnsupportedUnitFrame(PetFrame)
        end
        ForEachCompactFrame(function(memberFrame)
            if not FrameNeedsSafetyPoll(memberFrame) then
                return
            end
            SetFrameClipOverflow(memberFrame, memberFrame.healthBar, true)
            if memberFrame.healthBar and memberFrame.healthBar.SetClipsChildren then
                memberFrame.healthBar:SetClipsChildren(false)
            end
            SafeUpdateCompactFrame(memberFrame)
        end)
    end)
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded(addonName, InitializeAddon)
else
    local bootstrap = CreateFrame("Frame")
    bootstrap:RegisterEvent("ADDON_LOADED")
    bootstrap:SetScript("OnEvent", function(_, event, loadedName)
        if event == "ADDON_LOADED" and loadedName == addonName then
            bootstrap:UnregisterEvent("ADDON_LOADED")
            InitializeAddon()
        end
    end)
end
