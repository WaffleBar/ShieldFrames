local addonName, ns = ...

ShieldFramesDB = ShieldFramesDB or {}

local ADDON_DESCRIPTION = "ShieldFrames is a small and lightweight addon that displays absorb shields on unit frames. The goal is to provide important shield information at a glance without clutter or complexity."

local function DB()
    return ns.GetDB()
end

local function RefreshFrames()
    if ns.RefreshAllFrames then
        ns.RefreshAllFrames()
    end
end

local function RefreshFramesDeferred()
    C_Timer.After(0, RefreshFrames)
end

local function CreateCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        addonName .. "_" .. key,
        Settings.VarType.Boolean,
        label,
        ns.defaults[key],
        function()
            if DB()[key] == nil then
                return ns.defaults[key]
            end
            return DB()[key]
        end,
        function(value)
            DB()[key] = value
        end
    )

    local init = Settings.CreateCheckbox(category, setting, tooltip)
    setting:SetValueChangedCallback(RefreshFramesDeferred)
    return init
end

local function FormatOpacityValue(value)
    return string.format("%.2f", value / 100)
end

local function CreateOpacitySlider(category, key, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        addonName .. "_" .. key,
        Settings.VarType.Number,
        label,
        ns.defaults[key],
        function()
            return DB()[key] or ns.defaults[key]
        end,
        function(value)
            DB()[key] = math.floor(value + 0.5)
        end
    )

    local options = Settings.CreateSliderOptions(5, 100, 5)
    if options.SetMinLabel then
        options:SetMinLabel("Low")
    end
    if options.SetMaxLabel then
        options:SetMaxLabel("High")
    end
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatOpacityValue)

    local init = Settings.CreateSlider(category, setting, options, tooltip)
    setting:SetValueChangedCallback(RefreshFramesDeferred)
    return init
end

local function GetGlowColorComponents()
    local color = DB().glowColor
    if type(color) ~= "table" then
        color = ns.defaults.glowColor
    end
    return color.r or ns.defaults.glowColor.r,
        color.g or ns.defaults.glowColor.g,
        color.b or ns.defaults.glowColor.b
end

local function SetGlowColor(r, g, b, shouldRefresh)
    DB().glowColor = { r = r, g = g, b = b }
    if shouldRefresh ~= false then
        RefreshFramesDeferred()
    end
end

local function RestorePickerColor(setColor, previousR, previousG, previousB, onSwatchUpdate)
    setColor(previousR, previousG, previousB, false)
    if onSwatchUpdate then
        onSwatchUpdate()
    end
    if ns.RestoreAllBlizzGlowFadeStates then
        ns.RestoreAllBlizzGlowFadeStates()
    end
    RefreshFramesDeferred()
end

local function PrepareColorPickerFrame(anchorFrame)
    if not ColorPickerFrame then
        return
    end

    ColorPickerFrame:Hide()
    ColorPickerFrame:SetParent(UIParent)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    local frameLevel = 1000
    if anchorFrame and anchorFrame.GetFrameLevel then
        frameLevel = anchorFrame:GetFrameLevel() + 100
    elseif SettingsPanel and SettingsPanel.GetFrameLevel then
        frameLevel = SettingsPanel:GetFrameLevel() + 100
    end
    ColorPickerFrame:SetFrameLevel(frameLevel)
    ColorPickerFrame:SetClampedToScreen(true)
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function OpenRGBColorPicker(getComponents, setColor, onSwatchUpdate, anchorFrame)
    if not ColorPickerFrame then
        return
    end

    local r, g, b = getComponents()
    local previousR, previousG, previousB = r, g, b
    local settingsWasOpen = SettingsPanel and SettingsPanel:IsShown()
    local restoredSettings = false

    local function ApplyColor(newR, newG, newB)
        setColor(newR, newG, newB)
        if onSwatchUpdate then
            onSwatchUpdate()
        end
    end

    local function RestoreSettingsPanel()
        if restoredSettings or not settingsWasOpen then
            return
        end
        restoredSettings = true
        C_Timer.After(0, function()
            if Settings and Settings.OpenToCategory and ns.categoryID then
                Settings.OpenToCategory(ns.categoryID)
            elseif SettingsPanel then
                ShowUIPanel(SettingsPanel)
            end
        end)
    end

    local function OnPickerCancel(restore)
        local r, g, b

        if type(restore) == "table" then
            r = restore.r or restore[1]
            g = restore.g or restore[2]
            b = restore.b or restore[3]
        end

        if not r and ColorPickerFrame.GetPreviousValues then
            r, g, b = ColorPickerFrame:GetPreviousValues()
        end

        if r then
            RestorePickerColor(setColor, r, g, b, onSwatchUpdate)
        else
            RestorePickerColor(setColor, previousR, previousG, previousB, onSwatchUpdate)
        end
    end

    local function BeginColorPickerSession()
        if settingsWasOpen then
            HideUIPanel(SettingsPanel)
        end

        PrepareColorPickerFrame(anchorFrame)

        local previousOnHide = ColorPickerFrame:GetScript("OnHide")
        ColorPickerFrame:SetScript("OnHide", function(self, ...)
            if previousOnHide then
                previousOnHide(self, ...)
            end
            RestoreSettingsPanel()
            self:SetScript("OnHide", previousOnHide)
        end)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        BeginColorPickerSession()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                ApplyColor(ColorPickerFrame:GetColorRGB())
            end,
            cancelFunc = OnPickerCancel,
        })
        return
    end

    BeginColorPickerSession()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = previousR, g = previousG, b = previousB }
    ColorPickerFrame.func = function()
        ApplyColor(ColorPickerFrame:GetColorRGB())
    end
    ColorPickerFrame.cancelFunc = OnPickerCancel
    ColorPickerFrame.swatchFunc = function()
        ApplyColor(ColorPickerFrame:GetColorRGB())
    end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
end

local function HideListElementChrome(frame)
    if frame.Checkbox then
        frame.Checkbox:Hide()
    end
    if frame.Button then
        frame.Button:Hide()
    end
    if frame.Control then
        frame.Control:Hide()
    end
    if frame.NewFeature then
        frame.NewFeature:Hide()
    end
end

local function UpdateGlowSwatch(swatch)
    if not swatch then
        return
    end

    local r, g, b = GetGlowColorComponents()
    if swatch.UpdateColor then
        swatch:UpdateColor(r, g, b)
    elseif swatch.Swatch and swatch.Swatch.SetColorRGB then
        swatch.Swatch:SetColorRGB(r, g, b)
    elseif swatch.SetColorRGB then
        swatch:SetColorRGB(r, g, b)
    elseif swatch.Swatch and swatch.Swatch.SetColorTexture then
        swatch.Swatch:SetColorTexture(r, g, b)
    elseif swatch.ColorFill and swatch.ColorFill.SetColorTexture then
        swatch.ColorFill:SetColorTexture(r, g, b)
    elseif swatch.Color and swatch.Color.SetColorTexture then
        swatch.Color:SetColorTexture(r, g, b)
    end
end

local COLOR_PICKER_WIDTH = 140
local COLOR_PICKER_HEIGHT = 26
local COLOR_PICKER_SWATCH_MARGIN = 5
local COLOR_PICKER_ARROW_ZONE = 36

local function CreateSimpleArrow(parent)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 6)
    arrow:SetPoint("CENTER", parent, "CENTER", 0, 0)

    local ok = pcall(function()
        arrow:SetAtlas("common-icon-backarrow")
        if arrow.SetRotation then
            arrow:SetRotation(math.rad(90))
        end
        if arrow.SetDesaturated then
            arrow:SetDesaturated(true)
        end
        arrow:SetVertexColor(0.62, 0.62, 0.62)
    end)

    if not ok then
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        arrow:SetTexCoord(0.25, 0.75, 0.3, 0.7)
        arrow:SetVertexColor(0.62, 0.62, 0.62)
    end

    return arrow
end

local function CreateGlowColorPickerButton(parent, onClick)
    local picker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    picker:SetSize(COLOR_PICKER_WIDTH, COLOR_PICKER_HEIGHT)

    picker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    picker:SetBackdropColor(0.11, 0.11, 0.11, 1)
    picker:SetBackdropBorderColor(0.48, 0.48, 0.48, 1)

    local swatchWidth = COLOR_PICKER_WIDTH - COLOR_PICKER_ARROW_ZONE - (COLOR_PICKER_SWATCH_MARGIN * 2)
    local swatchHeight = COLOR_PICKER_HEIGHT - (COLOR_PICKER_SWATCH_MARGIN * 2)

    picker.Swatch = CreateFrame("Frame", nil, picker, "BackdropTemplate")
    picker.Swatch:SetSize(swatchWidth, swatchHeight)
    picker.Swatch:SetPoint("LEFT", COLOR_PICKER_SWATCH_MARGIN, 0)
    picker.Swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    picker.ArrowZone = CreateFrame("Frame", nil, picker)
    picker.ArrowZone:SetPoint("TOPRIGHT", -COLOR_PICKER_SWATCH_MARGIN, -COLOR_PICKER_SWATCH_MARGIN)
    picker.ArrowZone:SetPoint("BOTTOMRIGHT", COLOR_PICKER_SWATCH_MARGIN, COLOR_PICKER_SWATCH_MARGIN)
    picker.ArrowZone:SetWidth(COLOR_PICKER_ARROW_ZONE)

    picker.Arrow = CreateSimpleArrow(picker.ArrowZone)

    function picker:UpdateColor(r, g, b)
        self.Swatch:SetBackdropColor(r, g, b, 1)
        self.Swatch:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
    end

    picker:SetScript("OnClick", onClick)
    picker:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.62, 0.62, 0.62, 1)
    end)
    picker:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.48, 0.48, 0.48, 1)
    end)

    return picker
end

local function CanUseCustomInitializers()
    return ScrollBoxFactoryInitializerMixin
        and SettingsElementHierarchyMixin
        and SettingsSearchableElementMixin
        and CreateFromMixins
end

local function CreateAboutDescriptionInitializer()
    local AboutDescriptionInitializer = CreateFromMixins(
        ScrollBoxFactoryInitializerMixin,
        SettingsElementHierarchyMixin,
        SettingsSearchableElementMixin
    )

    function AboutDescriptionInitializer:Init()
        ScrollBoxFactoryInitializerMixin.Init(self, "SettingsListElementTemplate")
        self.data = {
            name = "About ShieldFrames",
            tooltip = ADDON_DESCRIPTION,
        }
        self:AddSearchTags("About", "ShieldFrames", "description")
    end

    function AboutDescriptionInitializer:GetExtent()
        return 84
    end

    function AboutDescriptionInitializer:InitFrame(frame)
        frame:SetSize(280, 84)
        HideListElementChrome(frame)

        if not frame.cbrHandles then
            frame.cbrHandles = Settings.CreateCallbackHandleContainer()
        end

        if frame.Text then
            frame.Text:Hide()
        end

        if not frame.descBox then
            frame.descBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.descBox:SetPoint("TOPLEFT", 16, -4)
            frame.descBox:SetPoint("BOTTOMRIGHT", -16, 4)
            frame.descBox:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            frame.descBox:SetBackdropColor(0.09, 0.09, 0.09, 0.92)
            frame.descBox:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

            frame.descText = frame.descBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            frame.descText:SetPoint("TOPLEFT", 10, -8)
            frame.descText:SetPoint("BOTTOMRIGHT", -10, 8)
            frame.descText:SetJustifyH("LEFT")
            frame.descText:SetJustifyV("TOP")
            frame.descText:SetWordWrap(true)
            frame.descText:SetSpacing(2)
            frame.descText:SetText(ADDON_DESCRIPTION)
        end
    end

    function AboutDescriptionInitializer:Resetter(frame)
        if frame.cbrHandles then
            frame.cbrHandles:Unregister()
        end
    end

    local initializer = CreateFromMixins(AboutDescriptionInitializer)
    initializer:Init()
    return initializer
end

local function CreateGlowColorInitializer()
    local GlowColorInitializer = CreateFromMixins(
        ScrollBoxFactoryInitializerMixin,
        SettingsElementHierarchyMixin,
        SettingsSearchableElementMixin
    )

    function GlowColorInitializer:Init()
        ScrollBoxFactoryInitializerMixin.Init(self, "SettingsListElementTemplate")
        self.data = {
            name = "Glow Color",
            tooltip = "Tint for the overshield edge glow.",
        }
        self:AddSearchTags("Glow Color", "color")
    end

    function GlowColorInitializer:GetExtent()
        return 26
    end

    function GlowColorInitializer:InitFrame(frame)
        frame:SetSize(280, 26)
        HideListElementChrome(frame)

        if not frame.cbrHandles then
            frame.cbrHandles = Settings.CreateCallbackHandleContainer()
        end

        frame.data = self.data
        frame.Text:SetFontObject("GameFontNormal")
        frame.Text:SetText("Glow Color")
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("LEFT", 16, 0)
        frame.Text:SetPoint("RIGHT", frame, "CENTER", -85, 0)
        frame.Text:SetJustifyH("LEFT")
        frame.Text:Show()

        local function UpdateSwatch()
            UpdateGlowSwatch(frame.colorPicker)
        end

        if not frame.colorPicker then
            frame.colorPicker = CreateGlowColorPickerButton(frame, function(button)
                OpenRGBColorPicker(GetGlowColorComponents, SetGlowColor, UpdateSwatch, button)
            end)
            frame.colorPicker:ClearAllPoints()
            frame.colorPicker:SetPoint("LEFT", frame, "CENTER", -74, 0)
            UpdateSwatch()
        else
            UpdateSwatch()
        end
    end

    function GlowColorInitializer:Resetter(frame)
        if frame.cbrHandles then
            frame.cbrHandles:Unregister()
        end
    end

    local initializer = CreateFromMixins(GlowColorInitializer)
    initializer:Init()
    return initializer
end

local function CreateAboutDescription(layout)
    if CanUseCustomInitializers() then
        layout:AddInitializer(CreateAboutDescriptionInitializer())
        return
    end

    layout:AddInitializer(CreateSettingsButtonInitializer(
        addonName,
        "View on GitHub",
        function()
            if OpenURL then
                OpenURL("https://github.com/WaffleBar/ShieldFrames")
            end
        end,
        ADDON_DESCRIPTION,
        true
    ))
end

local function CreateGlowColorRow(layout)
    if CanUseCustomInitializers() then
        layout:AddInitializer(CreateGlowColorInitializer())
        return
    end

    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Glow Color",
        "Choose Color",
        function()
            OpenRGBColorPicker(GetGlowColorComponents, SetGlowColor)
        end,
        "Tint for the overshield edge glow.",
        true
    ))
end

local function InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
    Settings.RegisterAddOnCategory(category)
    ns.categoryID = category:GetID()

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("About"))
    CreateAboutDescription(layout)

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))

    CreateCheckbox(
        category,
        "enabled",
        "Enable ShieldFrames",
        "Show overshield absorb overlays on supported Blizzard unit frames."
    )

    CreateOpacitySlider(
        category,
        "overlayOpacity",
        "Overlay Opacity",
        "Transparency of the overshield fill drawn over the health bar."
    )

    CreateCheckbox(
        category,
        "showGlow",
        "Show Edge Glow",
        "Draw a bright edge on the left side of the overshield overlay."
    )

    CreateOpacitySlider(
        category,
        "glowOpacity",
        "Glow Opacity",
        "Brightness of the overshield edge glow."
    )

    CreateGlowColorRow(layout)
end

EventUtil.ContinueOnPlayerLogin(function()
    if ns.MigrateSavedSettings then
        ns.MigrateSavedSettings()
    elseif ns.MergeDefaults then
        ns.MergeDefaults()
    end
    InitializeSettings()
end)
