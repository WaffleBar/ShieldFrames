local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7
local OVERLAY_TILE_SIZE = 32
local STRIPE_PATTERN_ALPHA = 0.85
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

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeNumber(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    return value
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
end

local function ShouldShowOvershieldGlow(overshieldAmount, fill)
    local hasOvershield = IsPositiveAmount(overshieldAmount)
    if hasOvershield ~= nil then
        return hasOvershield
    end

    local width = fill and SafeNumber(fill:GetWidth())
    return SafeGreaterThan(width, 0.5) == true
end

local function MidnightFrameHasOvershield(frame, overshieldAmount, totalAbsorb)
    local hasOvershield = IsPositiveAmount(overshieldAmount)
    if hasOvershield ~= nil then
        return hasOvershield
    end

    local ok, blizzGlowActive = pcall(FrameShowsOvershieldGlow, frame)
    if ok and blizzGlowActive then
        return true
    end

    if frame.ShieldFramesOvershieldActive then
        local noAbsorb = SafeLessOrEqual(totalAbsorb, 0)
        if noAbsorb == true then
            return false
        end
        return true
    end

    return false
end

local function GetUnitHealthValues(frame, unit)
    local healthBar = frame.healthbar or frame.healthBar
    if not healthBar then
        return
    end

    local curHealth = SafeNumber(healthBar:GetValue())
    local _, maxHealth = healthBar:GetMinMaxValues()
    maxHealth = SafeNumber(maxHealth)

    if (not curHealth or not maxHealth) and unit then
        curHealth = SafeNumber(UnitHealth(unit))
        maxHealth = SafeNumber(UnitHealthMax(unit))
    end

    return curHealth, maxHealth, healthBar
end

local function IsEnabled()
    return GetDB().enabled ~= false
end

local function GetOverlaySettings()
    local db = GetDB()
    return {
        overlayAlpha = (db.overlayOpacity or ns.defaults.overlayOpacity) / 100,
        overlayColor = db.overlayColor or ns.defaults.overlayColor,
        showGlow = db.showGlow ~= false,
        glowAlpha = (db.glowOpacity or ns.defaults.glowOpacity) / 100,
        glowColor = db.glowColor or ns.defaults.glowColor,
    }
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
    if not frame.ShieldFramesOverlay then
        local tint = healthBar:CreateTexture(nil, "OVERLAY", nil, 5)
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:Hide()

        local overlay = healthBar:CreateTexture(nil, "OVERLAY", nil, 6)
        overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        overlay.tileSize = OVERLAY_TILE_SIZE
        overlay:Hide()

        local glow = healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        glow:SetBlendMode("ADD")
        glow:SetWidth(16)
        glow:Hide()

        frame.ShieldFramesTint = tint
        frame.ShieldFramesOverlay = overlay
        frame.ShieldFramesGlow = glow
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
    if frame.ShieldFramesOverlayBar and not frame.ShieldFramesOverlayBar:IsForbidden() then
        frame.ShieldFramesOverlayBar:Hide()
    end
    if frame.ShieldFramesOverlayClip and not frame.ShieldFramesOverlayClip:IsForbidden() then
        frame.ShieldFramesOverlayClip:Hide()
    end
    RestoreBlizzOvershieldGlow(frame, frame.overAbsorbGlow)
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

local function AnchorOverlayToFill(overlay, healthBar, fill, parent)
    overlay:SetParent(parent or healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
end

local function ApplyStripePatternOverlay(frame, healthBar, fill, parent)
    local overlay = frame and frame.ShieldFramesOverlay
    if not overlay or overlay:IsForbidden() or not fill then
        return
    end

    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    AnchorOverlayToFill(overlay, healthBar, fill, parent)
    ApplyTiledOverlayTexture(overlay, fill, healthBar, OVERLAY_TILE_SIZE)
    overlay:SetVertexColor(1, 1, 1, STRIPE_PATTERN_ALPHA)
    overlay:Show()
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
    local overlayColor = settings.overlayColor

    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", healthFill, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
    clip:Show()

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, maxHealth)
    bar:SetReverseFill(true)
    bar:SetValue(absorbAmount)
    bar:SetStatusBarColor(
        overlayColor.r or 1,
        overlayColor.g or 1,
        overlayColor.b or 1,
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

    ApplyStripePatternOverlay(frame, healthBar, fill, bar)

    if glow and not glow:IsForbidden() and settings.showGlow and ShouldShowOvershieldGlow(overshieldAmount, fill) then
        local color = settings.glowColor
        glow:SetParent(bar)
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", fill, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    return true
end

local function ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, tileSize, fillAnchor)
    overlayWidth = SafeNumber(overlayWidth)
    if not overlay or overlay:IsForbidden() or not overlayWidth or overlayWidth <= 0 then
        return false
    end

    local settings = GetOverlaySettings()
    tileSize = tileSize or overlay.tileSize or OVERLAY_TILE_SIZE
    local overlayColor = settings.overlayColor
    local tint = frame and frame.ShieldFramesTint

    if tint and not tint:IsForbidden() then
        tint:SetParent(healthBar)
        tint:ClearAllPoints()
        tint:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        tint:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        if fillAnchor then
            tint:SetPoint("TOPLEFT", fillAnchor, "TOPLEFT", 0, 0)
            tint:SetPoint("BOTTOMLEFT", fillAnchor, "BOTTOMLEFT", 0, 0)
        else
            tint:SetWidth(overlayWidth)
        end
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        tint:SetVertexColor(
            overlayColor.r or 1,
            overlayColor.g or 1,
            overlayColor.b or 1,
            settings.overlayAlpha
        )
        tint:Show()
    end

    overlay:SetParent(healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    if fillAnchor then
        overlay:SetPoint("TOPLEFT", fillAnchor, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", fillAnchor, "BOTTOMLEFT", 0, 0)
        ApplyTiledOverlayTexture(overlay, fillAnchor, healthBar, tileSize)
    else
        overlay:SetWidth(overlayWidth)
        local totalHeight = SafeOverlayHeight(healthBar)
        overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
    end
    overlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
    overlay:SetVertexColor(1, 1, 1, STRIPE_PATTERN_ALPHA)
    overlay:Show()

    if glow and not glow:IsForbidden() and settings.showGlow then
        local color = settings.glowColor
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
        glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
        glow:Show()
    elseif glow and not glow:IsForbidden() then
        glow:Hide()
    end

    return true
end

local function UpdateMidnightOvershield(frame, healthBar, unit)
    local blizzGlow = frame.overAbsorbGlow
    local totalAbsorb, overshieldAmount, maxHealth = GetCalculatorAbsorbValues(unit)

    if not MidnightFrameHasOvershield(frame, overshieldAmount, totalAbsorb) then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
        return
    end

    if not totalAbsorb or not maxHealth then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
        return
    end

    SetFrameOvershieldActive(frame, true)
    local applied = ApplyOvershieldBar(frame, healthBar, totalAbsorb, maxHealth, overshieldAmount)

    if applied and blizzGlow then
        HideBlizzOvershieldGlow(frame, blizzGlow)
    elseif not applied then
        SetFrameOvershieldActive(frame, false)
        HideOvershieldDisplay(frame)
    end
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
        local overlayColor = settings.overlayColor
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
                overlayColor.r or 1,
                overlayColor.g or 1,
                overlayColor.b or 1,
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
        overlay:SetVertexColor(1, 1, 1, STRIPE_PATTERN_ALPHA)
        overlay:Show()

        if glow and not glow:IsForbidden() and settings.showGlow then
            local color = settings.glowColor
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
            glow:Show()
        elseif glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    EnsureCustomTextures(frame, healthBar)
    ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, overlay.tileSize)
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

    local healthBar = frame.healthbar or frame.healthBar
    if not healthBar or healthBar:IsForbidden() then
        return
    end

    if UsesHealPredictionCalculator() then
        UpdateMidnightOvershield(frame, healthBar, frame.unit)
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
    ApplyOverlayAndGlow(frame, healthBar, overlay, glow, overlayWidth, 32)

    if frame.overAbsorbGlow and not frame.overAbsorbGlow:IsForbidden() then
        frame.overAbsorbGlow:Hide()
    end
end

local function SafeUpdateCompactFrame(frame)
    pcall(UpdateCompactFrameInternal, frame)
end

local function SafeUpdateUnitFrame(frame)
    pcall(UpdateUnitFrame, frame)
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
        SafeUpdateUnitFrame(PetFrame)
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
        SafeUpdateUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(memberFrame)
        SafeUpdateCompactFrame(memberFrame)
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
            if PlayerFrame then
                UpdateMidnightOvershield(PlayerFrame, PlayerFrame.healthbar, unit)
            end

            local glowShown = PlayerFrame and FrameShowsOvershieldGlow(PlayerFrame)
            ChatPrint("|cff00ccffShieldFrames|r blizz overAbsorbGlow active: " .. tostring(glowShown))

            local _, overshieldAmount = GetCalculatorAbsorbValues(unit)
            if overshieldAmount ~= nil and CanAccessValue(overshieldAmount) then
                ChatPrint("|cff00ccffShieldFrames|r calculator overshield: " .. tostring(overshieldAmount))
            else
                ChatPrint("|cff00ccffShieldFrames|r calculator overshield: secret/unavailable")
            end

            local bar = PlayerFrame and PlayerFrame.ShieldFramesOverlayBar
            local barShown = bar and bar:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom overlay bar: " .. tostring(not not barShown))

            if barShown and bar then
                local fill = bar:GetStatusBarTexture()
                local width = fill and fill:GetWidth()
                if SafeNumber(width) and width > 0 then
                    ChatPrint("|cff00ccffShieldFrames|r overlay width: " .. tostring(math.floor(width + 0.5)))
                else
                    ChatPrint("|cff00ccffShieldFrames|r overlay width: secret/unavailable")
                end
            end

            local glowActive = PlayerFrame
                and PlayerFrame.ShieldFramesGlow
                and PlayerFrame.ShieldFramesGlow:IsShown()
            ChatPrint("|cff00ccffShieldFrames|r custom glow: " .. tostring(not not glowActive))

            if not glowShown and not barShown then
                ChatPrint("|cff00ccffShieldFrames|r no overshield glow. Cast a barrier at full HP to test.")
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
    PrintDebugInfo()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        ns.RefreshAllFrames()
        return
    end

    if unit then
        RefreshUnitFrameByUnit(unit)
    else
        ns.RefreshAllFrames()
    end
end)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    ns.MergeDefaults()

    hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
        SafeUpdateCompactFrame(frame)
    end)

    hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
        SafeUpdateUnitFrame(frame)
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
        if PetFrame and PetFrame.unit then
            SafeUpdateUnitFrame(PetFrame)
        end
    end)

end)
