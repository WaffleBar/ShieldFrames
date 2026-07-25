local addonName, ns = ...

local GLOW_EDGE_OFFSET = -7

ns.defaults = {
    enabled = true,
    overlayOpacity = 40,
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

local function IsEnabled()
    return GetDB().enabled ~= false
end

local function GetOverlaySettings()
    local db = GetDB()
    return {
        overlayAlpha = (db.overlayOpacity or ns.defaults.overlayOpacity) / 100,
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

    return overshield
end

local function ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth)
    if not overlay or overlay:IsForbidden() or overlayWidth <= 0 then
        return false
    end

    local settings = GetOverlaySettings()
    local tileSize = overlay.tileSize or 32
    local _, totalHeight = healthBar:GetSize()

    overlay:SetParent(healthBar)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetWidth(overlayWidth)
    overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
    overlay:SetVertexColor(1, 1, 1, settings.overlayAlpha)
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

local function UpdateCompactFrameInternal(frame)
    if not IsEnabled() or not frame or frame:IsForbidden() or not frame.displayedUnit or not frame.healthBar then
        return
    end

    local healthBar = frame.healthBar
    local overlay = frame.totalAbsorbOverlay
    local glow = frame.overAbsorbGlow
    local absorbBar = frame.totalAbsorb

    if not overlay or overlay:IsForbidden() then
        return
    end

    local curHealth = healthBar:GetValue()
    local _, maxHealth = healthBar:GetMinMaxValues()
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

    local barWidth = healthBar:GetWidth()
    if barWidth <= 0 then
        return
    end

    local fillWidth = (curHealth / maxHealth) * barWidth
    local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
    if overlayWidth <= 0 then
        return
    end

    local anchor = healthBar
    if absorbBar and not absorbBar:IsForbidden() and absorbBar:IsShown() then
        overlay:ClearAllPoints()
        overlay:SetParent(healthBar)
        overlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
        overlay:SetWidth(overlayWidth)
        local tileSize = overlay.tileSize or 32
        local _, totalHeight = healthBar:GetSize()
        overlay:SetTexCoord(0, overlayWidth / tileSize, 0, totalHeight / tileSize)
        overlay:SetVertexColor(1, 1, 1, GetOverlaySettings().overlayAlpha)
        overlay:Show()

        if glow and not glow:IsForbidden() and GetOverlaySettings().showGlow then
            local color = GetOverlaySettings().glowColor
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, GetOverlaySettings().glowAlpha)
            glow:Show()
        elseif glow and not glow:IsForbidden() then
            glow:Hide()
        end
        return
    end

    ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth)
end

function ns.UpdateCompactFrame(frame)
    UpdateCompactFrameInternal(frame)
end

local function UpdateUnitFrame(frame)
    if not IsEnabled() or not frame or frame:IsForbidden() or not frame.unit or not frame.healthbar then
        return
    end

    if not frame.myHealPredictionBar then
        return
    end

    local healthBar = frame.healthbar
    local absorbBar = frame.totalAbsorbBar
    local glow = frame.overAbsorbGlow
    local overlay = frame.totalAbsorbBarOverlay or frame.totalAbsorbOverlay

    if not absorbBar or absorbBar:IsForbidden() or not glow or glow:IsForbidden() then
        return
    end

    local curHealth = healthBar:GetValue()
    local _, maxHealth = healthBar:GetMinMaxValues()
    if not curHealth or curHealth <= 0 or not maxHealth or maxHealth <= 0 then
        return
    end

    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
    if totalAbsorb <= 0 then
        glow:Hide()
        return
    end

    local effectiveHealth = curHealth + totalAbsorb
    local healthBarTexture = healthBar:GetStatusBarTexture()
    local absorbFillMaskTexture = absorbBar.FillMask

    if effectiveHealth > maxHealth and absorbBar.UpdateFillPosition and healthBarTexture then
        local xOffset = (maxHealth / effectiveHealth) - 1
        absorbBar:UpdateFillPosition(healthBarTexture, totalAbsorb, xOffset)

        local overshield = GetOvershieldAmount(frame.unit, curHealth, maxHealth)
        if overshield > 0 and overlay and not overlay:IsForbidden() then
            local barWidth = healthBar:GetWidth()
            local fillWidth = (curHealth / maxHealth) * barWidth
            local overlayWidth = Clamp((overshield / maxHealth) * barWidth, 0, math.min(fillWidth, barWidth))
            ApplyOverlayAndGlow(healthBar, overlay, glow, overlayWidth)
            return
        end

        if absorbFillMaskTexture and not absorbFillMaskTexture:IsForbidden() then
            local settings = GetOverlaySettings()
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", absorbFillMaskTexture, "TOPLEFT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", absorbFillMaskTexture, "BOTTOMLEFT", GLOW_EDGE_OFFSET, 0)
            if settings.showGlow then
                local color = settings.glowColor
                glow:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, settings.glowAlpha)
                glow:Show()
            else
                glow:Hide()
            end
        end
        return
    end

    if glow and not glow:IsForbidden() then
        if healthBarTexture and not healthBarTexture:IsForbidden() then
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", healthBarTexture, "TOPRIGHT", GLOW_EDGE_OFFSET, 0)
            glow:SetPoint("BOTTOMLEFT", healthBarTexture, "BOTTOMRIGHT", GLOW_EDGE_OFFSET, 0)
            glow:SetAlpha(GetOverlaySettings().glowAlpha)
        else
            glow:Hide()
        end
    end
end

local function ForEachCompactFrame(callback)
    if type(callback) ~= "function" then
        return
    end

    if CompactPartyFrame and CompactPartyFrame.members then
        for _, frame in pairs(CompactPartyFrame.members) do
            callback(frame)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.flowFrames then
        for _, frame in ipairs(CompactPartyFrame.flowFrames) do
            callback(frame)
        end
    end

    for index = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. index]
        if frame then
            callback(frame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.flowFrames then
        for _, frame in ipairs(CompactRaidFrameContainer.flowFrames) do
            callback(frame)
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.groups then
        for _, group in pairs(CompactRaidFrameContainer.groups) do
            if group and group.flowFrames then
                for _, frame in ipairs(group.flowFrames) do
                    callback(frame)
                end
            end
        end
    end

    for index = 1, 40 do
        local frame = _G["CompactRaidFrame" .. index]
        if frame then
            callback(frame)
        end
    end
end

local function RefreshUnitFrameByUnit(unit)
    if not unit then
        return
    end

    if PlayerFrame and PlayerFrame.unit == unit then
        UpdateUnitFrame(PlayerFrame)
    end
    if TargetFrame and TargetFrame.unit == unit then
        UpdateUnitFrame(TargetFrame)
    end
    if FocusFrame and FocusFrame.unit == unit then
        UpdateUnitFrame(FocusFrame)
    end
    if PetFrame and PetFrame.unit == unit then
        UpdateUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(frame)
        if frame.displayedUnit == unit then
            UpdateCompactFrameInternal(frame)
        end
    end)
end

function ns.RefreshAllFrames()
    if PlayerFrame then
        UpdateUnitFrame(PlayerFrame)
    end
    if TargetFrame then
        UpdateUnitFrame(TargetFrame)
    end
    if FocusFrame then
        UpdateUnitFrame(FocusFrame)
    end
    if PetFrame then
        UpdateUnitFrame(PetFrame)
    end

    ForEachCompactFrame(function(frame)
        UpdateCompactFrameInternal(frame)
    end)
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
        UpdateCompactFrameInternal(frame)
    end)

    hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
        UpdateUnitFrame(frame)
    end)

    SLASH_SHIELDFRAMES1 = "/shieldframes"
    SLASH_SHIELDFRAMES2 = "/sf"
    SlashCmdList["SHIELDFRAMES"] = function(msg)
        msg = strtrim(string.lower(msg or ""))
        if msg == "debug" then
            local unit = "player"
            local absorb = UnitGetTotalAbsorbs(unit) or 0
            local health = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local overshield = GetOvershieldAmount(unit, health, maxHealth)
            print("|cff00ccffShieldFrames|r enabled:", tostring(IsEnabled()))
            print("|cff00ccffShieldFrames|r player absorb:", absorb, "overshield:", overshield or 0, "health:", health, "/", maxHealth)
            if PlayerFrame then
                print("|cff00ccffShieldFrames|r PlayerFrame overlay:", tostring(PlayerFrame.totalAbsorbBarOverlay ~= nil))
                print("|cff00ccffShieldFrames|r PlayerFrame heal prediction:", tostring(PlayerFrame.myHealPredictionBar ~= nil))
            end
            ns.RefreshAllFrames()
            return
        end

        if Settings and Settings.OpenToCategory and ns.categoryID then
            Settings.OpenToCategory(ns.categoryID)
        end
    end
end)
