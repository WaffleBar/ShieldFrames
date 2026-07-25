local addonName, ns = ...

local function DB()
    return ns.GetDB()
end

local function RefreshFrames()
    if ns.RefreshAllFrames then
        ns.RefreshAllFrames()
    end
end

local function CreateCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        key,
        Settings.VarType.Boolean,
        label,
        ns.defaults[key],
        function()
            return DB()[key]
        end,
        function(value)
            DB()[key] = value
        end
    )

    local init = Settings.CreateCheckbox(category, setting, tooltip)
    setting:SetValueChangedCallback(RefreshFrames)
    return init
end

local function CreateSlider(category, key, label, min, max, step, tooltip, formatValue)
    local setting = Settings.RegisterProxySetting(
        category,
        key,
        Settings.VarType.Number,
        label,
        ns.defaults[key],
        function()
            return DB()[key]
        end,
        function(value)
            DB()[key] = value
        end
    )

    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatValue or function(value)
        return string.format("%d%%", value)
    end)

    local init = Settings.CreateSlider(category, setting, options, tooltip)
    setting:SetValueChangedCallback(RefreshFrames)
    return init
end

local function GetGlowColorComponents()
    local color = DB().glowColor or ns.defaults.glowColor
    return color.r or 1, color.g or 1, color.b or 1
end

local function SetGlowColor(r, g, b)
    DB().glowColor = { r = r, g = g, b = b }
    RefreshFrames()
end

local function OpenGlowColorPicker()
    local r, g, b = GetGlowColorComponents()
    local previousR, previousG, previousB = r, g, b

    ColorPickerFrame:SetupColorPickerAndShow({
        r = r,
        g = g,
        b = b,
        hasOpacity = false,
        swatchFunc = function()
            SetGlowColor(ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = function()
            local previousValues = ColorPickerFrame:GetPreviousValues()
            if previousValues and previousValues.r then
                SetGlowColor(previousValues.r, previousValues.g, previousValues.b)
            else
                SetGlowColor(previousR, previousG, previousB)
            end
        end,
    })
end

local function OpenGitHub()
    if OpenURL then
        OpenURL("https://github.com/WaffleBar/ShieldFrames")
    end
end

local ADDON_DESCRIPTION = "ShieldFrames enhances Blizzard's default compact party and raid frames by visualizing overshield absorbs.|n|nInstead of a thin glow on the right edge of the health bar, ShieldFrames draws a semi-transparent overlay that extends leftward in proportion to the actual overshield value. The overlay never extends beyond the health bar frame.|n|nRequires Interface > Raid Frames > Display Incoming Heals."

local function InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("ShieldFrames")
    Settings.RegisterAddOnCategory(category)
    ns.categoryID = category:GetID()

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("About"))

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "ShieldFrames",
        "View on GitHub",
        OpenGitHub,
        ADDON_DESCRIPTION,
        true
    ))

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Overshield Display"))

    local enabledInit = CreateCheckbox(
        category,
        "enabled",
        "Enable ShieldFrames",
        "Show overshield absorb as a transparent bar extending left across Blizzard party and raid health bars. Requires Interface > Raid Frames > Display Incoming Heals."
    )

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Appearance"))

    local overlayOpacityInit = CreateSlider(
        category,
        "overlayOpacity",
        "Overlay Opacity",
        5,
        100,
        5,
        "Transparency of the overshield fill drawn over the health bar."
    )

    local glowInit = CreateCheckbox(
        category,
        "showGlow",
        "Show Edge Glow",
        "Draw a bright edge on the left side of the overshield overlay."
    )

    local glowOpacityInit = CreateSlider(
        category,
        "glowOpacity",
        "Glow Opacity",
        5,
        100,
        5,
        "Brightness of the overshield edge glow."
    )

    local glowColorInit = layout:AddInitializer(CreateSettingsButtonInitializer(
        "Glow Color",
        "Choose Color",
        OpenGlowColorPicker,
        "Tint for the overshield edge glow.",
        true
    ))

    overlayOpacityInit:SetParentInitializer(enabledInit, function()
        return DB().enabled
    end)
    overlayOpacityInit:AddShownPredicate(function()
        return DB().enabled
    end)

    glowInit:SetParentInitializer(enabledInit, function()
        return DB().enabled
    end)
    glowInit:AddShownPredicate(function()
        return DB().enabled
    end)

    glowOpacityInit:SetParentInitializer(glowInit, function()
        return DB().showGlow
    end)
    glowOpacityInit:AddShownPredicate(function()
        return DB().enabled and DB().showGlow
    end)

    glowColorInit:SetParentInitializer(glowInit, function()
        return DB().showGlow
    end)
    glowColorInit:AddShownPredicate(function()
        return DB().enabled and DB().showGlow
    end)
end

EventUtil.ContinueOnPlayerLogin(InitializeSettings)
