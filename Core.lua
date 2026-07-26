local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7
local OVERLAY_TILE_SIZE = 32
local GLOW_TEXTURE_WIDTH = 20
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
    if not glow:IsShown() then
        return false
    end
    -- Never read GetAlpha(); our SetAlpha(0) taints it into a secret value.
    return not frame.ShieldFramesBlizzGlowFaded
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

    if unit then
        local rawCur = UnitHealth(unit)
        local rawMax = UnitHealthMax(unit)
        local curHealth = rawCur ~= nil and CanAccessValue(rawCur) and SafeNumber(rawCur) or nil
        local maxHealth = rawMax ~= nil and CanAccessValue(rawMax) and SafeNumber(rawMax) or nil
        if curHealth or maxHealth then
            return curHealth, maxHealth, healthBar
        end
    end

    if UsesHealPredictionCalculator() then
        return nil, nil, healthBar
    end

    if not healthBar then
        return
    end

    local ok, curHealth, maxHealth = pcall(function()
        return healthBar:GetValue(), select(2, healthBar:GetMinMaxValues())
    end)
    if not ok then
        return
    end

    return SafeNumber(curHealth), SafeNumber(maxHealth), healthBar
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

local ABSORB_AURA_SPELL_IDS = {
    [235313] = true, -- Blazing Barrier
    [235450] = true, -- Prismatic Barrier
    [11426] = true,  -- Ice Barrier
    [77535] = true,  -- Blood Shield (Blood DK)
    [48707] = true,  -- Anti-Magic Shell
    [17] = true,     -- Power Word: Shield
    [184662] = true, -- Shield of Vengeance
    [271466] = true, -- Luminous Barrier
}

local MAGE_BARRIER_SPELL_IDS = {
    [235313] = true,
    [235450] = true,
    [11426] = true,
}

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

local function GetKnownAbsorbAuraData(unit)
    if not unit or not C_UnitAuras then
        return nil
    end

    for spellId in pairs(ABSORB_AURA_SPELL_IDS) do
        local aura = SafeGetAuraBySpellID(unit, spellId)
        if aura then
            return aura, spellId
        end
    end

    if C_UnitAuras.GetAuraDataByIndex then
        -- Never break on a nil slot: Midnight can omit secret auras mid-list.
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
            if ok and aura then
                local spellId = SafeAuraSpellId(aura)
                if spellId and ABSORB_AURA_SPELL_IDS[spellId] then
                    return aura, spellId
                end
            end
        end
    end

    return nil
end

local function UnitHasKnownAbsorbAura(unit)
    return GetKnownAbsorbAuraData(unit) ~= nil
end

local function UnitHasDamageBarrierAura(unit)
    return UnitHasKnownAbsorbAura(unit)
end

local function GetAbsorbFromKnownAura(unit)
    local aura = GetKnownAbsorbAuraData(unit)
    if not aura then
        return nil
    end

    local points = SafeAuraField(aura, "points")
    if not points then
        return nil
    end

    local sawReadableZero = false
    for index = 1, 32 do
        local point = SafeAuraField(points, index)
        if point == nil then
            break
        end
        if CanAccessValue(point) then
            local amount = SafeNumber(point)
            if amount and amount > 0 then
                return amount
            end
            if amount == 0 then
                sawReadableZero = true
            end
        end
    end

    if sawReadableZero then
        return 0
    end

    return nil
end

local function KnownAbsorbAuraIsDepleted(unit)
    return GetAbsorbFromKnownAura(unit) == 0
end

local function UnitHasKnownAbsorbCandidate(unit)
    if not UnitHasKnownAbsorbAura(unit) then
        return false
    end
    return not KnownAbsorbAuraIsDepleted(unit)
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

    -- Failed scan: keep cache in combat (Blood Shield aura lookups often fail under Midnight).
    if unit == "player" and UnitAffectingCombat(unit) then
        return
    end

    if UnitHasReadableAbsorb(unit) == false then
        frame.ShieldFramesKnownAbsorbAuraPresent = false
        return
    end

    frame.ShieldFramesKnownAbsorbAuraPresent = false
end

local function KnownAbsorbAuraEvidenceActive(frame, unit)
    if unit and UnitHasKnownAbsorbCandidate(unit) then
        return true
    end
    return frame and frame.ShieldFramesKnownAbsorbAuraPresent == true
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

local function HasRecentAbsorbEvent(frame)
    if not frame or not frame.ShieldFramesLastAbsorbEvent then
        return false
    end
    return (GetTime() - frame.ShieldFramesLastAbsorbEvent) < 12
end

local function ShouldPersistCombatSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount)
    if not HasCombatSecretAbsorbSignal(unit, totalAbsorb, overshieldAmount) then
        return false
    end
    if KnownAbsorbAuraEvidenceActive(frame, unit) then
        return true
    end
    if frame and frame.ShieldFramesLastAbsorbAmount and frame.ShieldFramesLastAbsorbAmount > 0 then
        return true
    end
    -- Blood DK: Death Strike fires UNIT_ABSORB_AMOUNT_CHANGED even when aura scans fail.
    return HasRecentAbsorbEvent(frame)
end

local function FrameShowsAbsorbBar(frame)
    local bar = frame and frame.totalAbsorb
    if not bar or (type(bar.IsForbidden) == "function" and bar:IsForbidden()) then
        return false
    end

    return bar:IsShown()
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

    return nil
end

local function GetKnownAbsorbAmount(unit, frame, healthBar, maxHealth)
    if not UnitHasKnownAbsorbAura(unit) then
        return nil
    end

    local _, spellId = GetKnownAbsorbAuraData(unit)
    local fromAura = GetAbsorbFromKnownAura(unit)
    if fromAura ~= nil then
        if fromAura > 0 then
            return fromAura
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

    if spellId and MAGE_BARRIER_SPELL_IDS[spellId] and maxHealth and CanAccessValue(maxHealth) then
        return maxHealth * 0.24
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

    if FrameHasBlizzOvershieldGlow(frame) then
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

    if HasSecretAbsorbValue(totalAbsorb, overshieldAmount) then
        if SafeLessOrEqual(totalAbsorb, 0) == true then
            return false
        end
        if FrameHasBlizzOvershieldGlow(frame) then
            return true
        end
        if KnownAbsorbAuraEvidenceActive(frame, unit) then
            return true
        end
        if ShouldPersistCombatSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount) then
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

    if FrameHasBlizzOvershieldGlow(frame) then
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
        if ShouldPersistCombatSecretAbsorb(frame, unit, totalAbsorb, overshieldAmount) then
            return false
        end
        if FrameHasBlizzOvershieldGlow(frame) then
            return false
        end
        if FrameShowsAbsorbBar(frame) then
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
            or ShouldPersistCombatSecretAbsorb(frame, unit, totalAbsorb, secretAbsorb or totalAbsorb)
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
}

local function HideBlizzAbsorbBar(bar, frame)
    if not bar or (type(bar.IsForbidden) == "function" and bar:IsForbidden()) then
        return false
    end

    if bar:IsShown() then
        bar:Hide()
        if frame then
            frame.ShieldFramesBlizzAbsorbHidden = true
        end
        return true
    end

    return false
end

local function SuppressBlizzAbsorbBars(frame, healthBar)
    for _, key in ipairs(BLIZZ_ABSORB_BAR_KEYS) do
        HideBlizzAbsorbBar(frame and frame[key], frame)
        if healthBar then
            HideBlizzAbsorbBar(healthBar[key], frame)
        end
    end
end

local function RestoreBlizzAbsorbBars(frame, healthBar)
    if not frame or not frame.ShieldFramesBlizzAbsorbHidden then
        return
    end

    for _, key in ipairs(BLIZZ_ABSORB_BAR_KEYS) do
        local bar = frame[key]
        if bar and not (type(bar.IsForbidden) == "function" and bar:IsForbidden()) then
            bar:Show()
        end

        if healthBar then
            bar = healthBar[key]
            if bar and not (type(bar.IsForbidden) == "function" and bar:IsForbidden()) then
                bar:Show()
            end
        end
    end

    frame.ShieldFramesBlizzAbsorbHidden = nil
end

local function SuppressBlizzAbsorbOverlays(frame, healthBar)
    for _, key in ipairs(BLIZZ_ABSORB_OVERLAY_KEYS) do
        local blizzOverlay = frame and frame[key]
        if blizzOverlay and not IsFrameForbidden(blizzOverlay) then
            blizzOverlay:Hide()
        end

        if healthBar then
            blizzOverlay = healthBar[key]
            if blizzOverlay and not IsFrameForbidden(blizzOverlay) then
                blizzOverlay:Hide()
            end
        end
    end

    SuppressBlizzAbsorbBars(frame, healthBar)
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
    if frame.ShieldFramesOverlayBar and not IsFrameForbidden(frame.ShieldFramesOverlayBar) then
        frame.ShieldFramesOverlayBar:Hide()
    end
    if frame.ShieldFramesOverlayClip and not IsFrameForbidden(frame.ShieldFramesOverlayClip) then
        frame.ShieldFramesOverlayClip:Hide()
    end
    RestoreBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
    RestoreBlizzAbsorbBars(frame, frame.healthbar or frame.healthBar)
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
    frame.ShieldFramesCachedBarWidth = nil
    frame.ShieldFramesLastMaxHealth = nil
    HideOvershieldDisplay(frame)
    frame.ShieldFramesLastApplyResult = false
end

local function EnsureOvershieldBar(frame, healthBar)
    if not frame.ShieldFramesOverlayClip then
        local clip = CreateFrame("Frame", nil, healthBar)
        clip:SetClipsChildren(true)
        clip:Hide()
        frame.ShieldFramesOverlayClip = clip
    end

    if not frame.ShieldFramesOverlayBar then
        local bar = CreateFrame("StatusBar", nil, frame.ShieldFramesOverlayClip)
        bar:SetFrameLevel(healthBar:GetFrameLevel() + 5)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetReverseFill(true)
        bar:Hide()
        frame.ShieldFramesOverlayBar = bar
    end

    local overlay, glow = EnsureCustomTextures(frame, healthBar)
    return frame.ShieldFramesOverlayBar, overlay, glow, frame.ShieldFramesOverlayClip
end

local function HideCustomTextures(frame)
    HideOvershieldDisplay(frame)
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
        glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
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
    clip:ClearAllPoints()

    local useExpandedClip = IsPositiveAmount(overshieldAmount)
    if useExpandedClip == nil then
        useExpandedClip = true
    elseif useExpandedClip == false and unit and frame then
        useExpandedClip = UnitHasReadableOvershield(unit, frame) == true
    end

    if useExpandedClip then
        clip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        clip:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
    else
        clip:SetPoint("TOPLEFT", healthFill, "TOPLEFT", 0, 0)
        clip:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
    end
    clip:Show()
end

local function ApplyStripePatternOverlay(frame, healthBar, fill, parent, settings, absorbAmount, maxHealth)
    local overlay = frame and frame.ShieldFramesOverlay
    if not overlay or overlay:IsForbidden() or not fill then
        return false
    end

    local tint = GetOverlayTintColor(settings)
    local sizingAbsorb = absorbAmount
    if (not sizingAbsorb or not CanAccessValue(sizingAbsorb)) and frame and frame.ShieldFramesLastAbsorbAmount then
        sizingAbsorb = frame.ShieldFramesLastAbsorbAmount
    end
    local sizingMax = maxHealth
    if (not sizingMax or not CanAccessValue(sizingMax)) and frame and frame.ShieldFramesLastMaxHealth then
        sizingMax = frame.ShieldFramesLastMaxHealth
    end
    local overlayWidth = ComputeAbsorbOverlayWidth(frame, healthBar, sizingAbsorb, sizingMax)
    local fillWidth = fill and SafeNumber(fill:GetWidth())

    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    if IsPositiveFinite(fillWidth) then
        -- Readable fill: lock stripe to the reverse-fill so glow/stripe cannot drift apart.
        AnchorOverlayToFill(overlay, healthBar, fill, parent)
        ApplyTiledOverlayTexture(overlay, fill, healthBar, OVERLAY_TILE_SIZE)
    elseif IsPositiveFinite(overlayWidth) then
        -- Secret/NaN fill width: size from absorb/max so the stripe still tracks.
        if not AnchorOverlayToHealthBarWidth(overlay, healthBar, overlayWidth, parent) then
            overlay:Hide()
            return false
        end
        local totalHeight = SafeOverlayHeight(healthBar)
        overlay:SetHorizTile(true)
        overlay:SetVertTile(true)
        overlay:SetTexCoord(0, overlayWidth / OVERLAY_TILE_SIZE, 0, totalHeight / OVERLAY_TILE_SIZE)
    else
        -- Never stretch-anchor to an unreadable/NaN fill — that paints a screen-wide stripe and lags.
        local fallbackWidth = SafeNumber(frame and frame.ShieldFramesLastOverlayWidth)
        if not IsPositiveFinite(fallbackWidth) then
            fallbackWidth = 48
        end
        if not AnchorOverlayToHealthBarWidth(overlay, healthBar, fallbackWidth, parent) then
            overlay:Hide()
            return false
        end
        local totalHeight = SafeOverlayHeight(healthBar)
        overlay:SetHorizTile(true)
        overlay:SetVertTile(true)
        overlay:SetTexCoord(0, fallbackWidth / OVERLAY_TILE_SIZE, 0, totalHeight / OVERLAY_TILE_SIZE)
        frame.ShieldFramesLastOverlayWidth = fallbackWidth
    end
    overlay:SetBlendMode("BLEND")
    overlay:SetVertexColor(tint.r or 1, tint.g or 1, tint.b or 1, settings.overlayAlpha)
    overlay:Show()
    return true
end

local function ApplyTiledStatusBarFill(fill, healthBar, tileSize)
    if not fill then
        return
    end

    tileSize = tileSize or OVERLAY_TILE_SIZE
    fill:SetHorizTile(true)
    fill:SetVertTile(true)

    local totalHeight = SafeOverlayHeight(healthBar)
    local left, right, top, bottom = GetTiledOverlayTexCoord(fill, tileSize, totalHeight)
    if left == 0 and right == 1 then
        left, right, top, bottom = GetTiledOverlayTexCoord(healthBar, tileSize, totalHeight)
    end
    fill:SetTexCoord(left, right, top, bottom)
end

local function ApplyOvershieldBar(frame, healthBar, absorbAmount, maxHealth, overshieldAmount)
    local bar, overlay, glow, clip = EnsureOvershieldBar(frame, healthBar)
    if not bar or bar:IsForbidden() or not clip or clip:IsForbidden() then
        return false
    end

    local healthFill = healthBar:GetStatusBarTexture()
    if not healthFill then
        return false
    end

    local settings = GetOverlaySettings()
    local tintColor = GetOverlayTintColor(settings)
    local unit = frame.unit or frame.displayedUnit

    -- Prefer a readable value for SetValue so the bar tracks in combat; secret SetValue stalls / NaNs.
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
    -- Secret SetMinMaxValues/SetValue can produce NaN fill widths that stretch across the screen.
    if not IsPositiveFinite(barAbsorb) or not IsPositiveFinite(barMax) then
        return false
    end

    AnchorOvershieldClip(clip, healthBar, healthFill, overshieldAmount, unit, frame)

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, barMax)
    bar:SetReverseFill(true)
    bar:SetValue(barAbsorb)
    bar:SetStatusBarColor(
        tintColor.r or 1,
        tintColor.g or 1,
        tintColor.b or 1,
        settings.overlayAlpha
    )
    bar:SetAlpha(1)
    bar:Show()

    local fill = bar:GetStatusBarTexture()
    if not fill then
        if overlay and not overlay:IsForbidden() then
            overlay:Hide()
        end
        if glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return false
    end

    if not ApplyStripePatternOverlay(frame, healthBar, fill, bar, settings, barAbsorb, barMax) then
        bar:Hide()
        if glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return false
    end

    local fillWidth = SafeNumber(fill:GetWidth())
    -- If the engine still handed back a broken fill, abandon the status-bar path.
    if fillWidth == nil then
        local rawWidth = fill.GetWidth and fill:GetWidth()
        if rawWidth ~= nil and not IsSecret(rawWidth) and not IsFiniteNumber(rawWidth) then
            bar:Hide()
            if overlay and not overlay:IsForbidden() then
                overlay:Hide()
            end
            if glow and not glow:IsForbidden() then
                glow:Hide()
            end
            return false
        end
    end

    local overlayWidth = ComputeAbsorbOverlayWidth(frame, healthBar, barAbsorb, barMax)
    local knownWidth = (IsPositiveFinite(overlayWidth) and overlayWidth)
        or (IsPositiveFinite(fillWidth) and fillWidth)
    -- Only suppress glow when width is known to be tiny.
    local canShowGlow = not (knownWidth and knownWidth > 0 and knownWidth < 8)
    local stripe = overlay

    if glow and not glow:IsForbidden() and settings.showGlow and canShowGlow and ShouldShowOvershieldGlow(frame, overshieldAmount, fill) then
        local color = settings.glowColor
        glow:SetParent(clip)
        glow:SetDrawLayer("OVERLAY", 7)
        glow:ClearAllPoints()
        -- Always pin to the stripe's left edge so leave-combat / readable-absorb updates cannot drift the glow into the health fill.
        if stripe and not IsFrameForbidden(stripe) and stripe:IsShown() then
            glow:SetPoint("TOPLEFT", stripe, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", stripe, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        elseif IsPositiveFinite(fillWidth) then
            glow:SetPoint("TOPLEFT", fill, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        elseif IsPositiveFinite(overlayWidth) then
            glow:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", -overlayWidth + GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", -overlayWidth + GLOW_EDGE_OFFSET, 0)
        else
            glow:Hide()
            -- Keep the stripe; glow is optional when anchors are unsafe.
            frame.ShieldFramesLastMaxHealth = barMax
            return true
        end
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    frame.ShieldFramesLastMaxHealth = barMax
    if IsPositiveFinite(knownWidth) then
        frame.ShieldFramesLastOverlayWidth = knownWidth
    end
    return true
end

local DEFAULT_BOOTSTRAP_OVERLAY_WIDTH = 48

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

local function ComputeBootstrapOverlayWidth(frame)
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
        local overlayWidth = ComputeBootstrapOverlayWidth(frame)
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
    local inCombat = unit and UnitAffectingCombat(unit)
    -- Prefer last readable absorb over a secret calculator value so combat sizing can update.
    local displayAbsorb = renderAbsorb
    if (not displayAbsorb or not CanAccessValue(displayAbsorb))
        and frame.ShieldFramesLastAbsorbAmount
        and frame.ShieldFramesLastAbsorbAmount > 0
        and (inCombat or KnownAbsorbAuraEvidenceActive(frame, unit))
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
        frame.ShieldFramesLastApplyPath = CanAccessValue(renderAbsorb) and "status-bar" or "status-bar-cached"
        if ApplyOvershieldBar(frame, healthBar, absorbForBar, max, overshieldAmount) then
            return true
        end
    end

    if not inCombat then
        -- Out of combat: only bootstrap when Blizzard still shows a live overshield glow.
        if not FrameHasBlizzOvershieldGlow(frame) then
            frame.ShieldFramesLastApplyPath = "skipped-ooc"
            return false
        end
    end

    frame.ShieldFramesLastApplyPath = "bootstrap"
    return ApplyOvershieldBootstrapOverlay(frame, healthBar, renderMaxHealth, overshieldAmount, unit)
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
    local blizzGlow = frame.overAbsorbGlow
    local totalAbsorb, overshieldAmount, maxHealth = GetCalculatorAbsorbValues(unit)

    if HasClearNoAbsorbSignal(frame, unit, totalAbsorb, overshieldAmount) then
        SetFrameOvershieldActive(frame, false)
        frame.ShieldFramesLastAbsorbAmount = nil
        frame.ShieldFramesPendingAbsorbEstimate = nil
        frame.ShieldFramesLastOverlayWidth = nil
        HideOvershieldDisplay(frame)
        frame.ShieldFramesLastApplyResult = false
        frame.ShieldFramesLastUpdateSkipReason = "clear-no-absorb"
        return
    end

    if not MidnightFrameHasAbsorb(frame, overshieldAmount, totalAbsorb, unit) then
        SetFrameOvershieldActive(frame, false)
        frame.ShieldFramesLastAbsorbAmount = nil
        frame.ShieldFramesPendingAbsorbEstimate = nil
        frame.ShieldFramesLastOverlayWidth = nil
        HideOvershieldDisplay(frame)
        frame.ShieldFramesLastApplyResult = false
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
        SuppressBlizzAbsorbOverlays(frame, healthBar)
        if blizzGlow then
            HideBlizzOvershieldGlow(frame, blizzGlow)
        end
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
            glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
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
        if frame and type(callback) == "function" then
            callback(frame)
        end
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
        if memberFrame.displayedUnit == unit then
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
            ChatPrint("|cff00ccffShieldFrames|r absorb aura depleted: " .. tostring(KnownAbsorbAuraIsDepleted(unit)))
            local bloodShield = SafeGetAuraBySpellID(unit, 77535)
            ChatPrint("|cff00ccffShieldFrames|r blood shield aura: " .. tostring(not not bloodShield))
            if playerFrame then
                ChatPrint("|cff00ccffShieldFrames|r recent absorb event: " .. tostring(HasRecentAbsorbEvent(playerFrame)))
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
                        local bootstrapWidth = ComputeBootstrapOverlayWidth(playerFrame)
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
            if barShown and textureShown then
                ChatPrint("|cff00ccffShieldFrames|r custom overlay texture: true (stripe on bar)")
            else
                ChatPrint("|cff00ccffShieldFrames|r custom overlay texture: " .. tostring(not not textureShown))
            end

            if barShown and bar then
                local fill = bar:GetStatusBarTexture()
                local width = fill and fill:GetWidth()
                if width ~= nil and not IsSecret(width) and not IsFiniteNumber(width) then
                    ChatPrint("|cff00ccffShieldFrames|r overlay width: nan (invalid layout — cleared on next safe update)")
                elseif IsPositiveFinite(width) then
                    ChatPrint("|cff00ccffShieldFrames|r overlay width: " .. tostring(math.floor(width + 0.5)))
                else
                    ChatPrint("|cff00ccffShieldFrames|r overlay width: secret/unavailable")
                end
            end

            local glowActive = playerFrame
                and playerFrame.ShieldFramesGlow
                and playerFrame.ShieldFramesGlow:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom glow: " .. tostring(not not glowActive))

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
        ns.RefreshAllFrames()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" then
            local stillHasShield = UnitHasKnownAbsorbCandidate("player")
                or ((GetAbsorbFromKnownAura("player") or 0) > 0)
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

    if event == "UNIT_ABSORB_AMOUNT_CHANGED" and unit == "player" and PlayerFrame then
        if KnownAbsorbAuraIsDepleted(unit) or UnitHasReadableAbsorb(unit) == false then
            PlayerFrame.ShieldFramesLastAbsorbEvent = nil
            PlayerFrame.ShieldFramesKnownAbsorbAuraPresent = false
            PlayerFrame.ShieldFramesLastAbsorbAmount = nil
        else
            PlayerFrame.ShieldFramesLastAbsorbEvent = GetTime()
            if UnitHasKnownAbsorbAura(unit) then
                PlayerFrame.ShieldFramesKnownAbsorbAuraPresent = true
            end
            local fromAura = GetAbsorbFromKnownAura(unit)
            if fromAura and fromAura > 0 then
                PlayerFrame.ShieldFramesLastAbsorbAmount = fromAura
            end
        end
    end

    if unit then
        RefreshUnitFrameByUnit(unit)
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
        DeferCompactFrameUpdate(frame)
    end)

    hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
        DeferUnitFrameUpdate(frame)
    end)

    C_Timer.NewTicker(0.15, function()
        if not IsEnabled() then
            return
        end
        if PlayerFrame and PlayerFrame.unit then
            SafeUpdateUnitFrame(PlayerFrame)
        end
        if TargetFrame and TargetFrame.unit then
            SafeUpdateUnitFrame(TargetFrame)
        end
        if FocusFrame and FocusFrame.unit then
            SafeUpdateUnitFrame(FocusFrame)
        end
        if PetFrame then
            ClearUnsupportedUnitFrame(PetFrame)
        end
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
