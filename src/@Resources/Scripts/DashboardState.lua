local currentLogoCode = 0
local currentLogo = "NONE"

local sourceMeasure
local listeningModeMeasure
local inputSignalMeasure
local displayModeCodeMeasure
local nowPlayingActiveMeasure
local nowPlayingSourceMeasure

local function contains(value, expected)
    return string.find(value, expected, 1, true) ~= nil
end

local function textValue(measure)
    if measure == nil then
        return ""
    end

    local value = measure:GetStringValue()
    if value == nil then
        return ""
    end

    return string.upper((value:gsub("^%s+", ""):gsub("%s+$", "")))
end

local function numberValue(measure)
    if measure == nil then
        return 0
    end

    return measure:GetValue()
end

local logoRegistry = {
    {
        internalIdentifier = "format.dolby_atmos",
        displayIdentifier = "DOLBY_ATMOS",
        code = 1,
        priority = 10,
        eligibilityRule = function(context)
            return context.displayModeCode == 1 or contains(context.format, "ATMOS")
        end
    },
    {
        internalIdentifier = "format.dts_x",
        displayIdentifier = "DTS_X",
        code = 2,
        priority = 20,
        eligibilityRule = function(context)
            return context.displayModeCode == 2
                or contains(context.format, "DTS:X")
                or contains(context.format, "NEURAL:X")
        end
    },
    {
        internalIdentifier = "source.schiit",
        displayIdentifier = "SCHIIT",
        code = 3,
        priority = 30,
        eligibilityRule = function(context)
            return context.source == "LYR+"
        end
    },
    {
        internalIdentifier = "service.apple_music",
        displayIdentifier = "APPLE_MUSIC",
        code = 4,
        priority = 40,
        eligibilityRule = function(context)
            return context.nowPlayingActive and contains(context.nowPlayingSource, "APPLE")
        end
    },
    {
        internalIdentifier = "service.plex",
        displayIdentifier = "PLEX",
        code = 5,
        priority = 50,
        eligibilityRule = function(context)
            return context.nowPlayingActive and contains(context.nowPlayingSource, "PLEX")
        end
    },
    {
        internalIdentifier = "source.windows",
        displayIdentifier = "WINDOWS",
        code = 6,
        priority = 60,
        eligibilityRule = function(context)
            return context.source == "HTPC"
        end
    }
}

function Initialize()
    sourceMeasure = SKIN:GetMeasure("DashboardRawSource")
    listeningModeMeasure = SKIN:GetMeasure("DashboardRawListeningMode")
    inputSignalMeasure = SKIN:GetMeasure("DashboardRawInputSignal")
    displayModeCodeMeasure = SKIN:GetMeasure("DashboardRawDisplayModeCode")
    nowPlayingActiveMeasure = SKIN:GetMeasure("DashboardRawNowPlayingActive")
    nowPlayingSourceMeasure = SKIN:GetMeasure("DashboardRawNowPlayingSource")

    table.sort(logoRegistry, function(left, right)
        return left.priority < right.priority
    end)
end

function Update()
    local context = {
        source = textValue(sourceMeasure),
        listeningMode = textValue(listeningModeMeasure),
        inputSignal = textValue(inputSignalMeasure),
        displayModeCode = numberValue(displayModeCodeMeasure),
        nowPlayingActive = numberValue(nowPlayingActiveMeasure) == 1,
        nowPlayingSource = textValue(nowPlayingSourceMeasure)
    }
    context.format = context.listeningMode .. " " .. context.inputSignal

    currentLogoCode = 0
    currentLogo = "NONE"

    for _, identity in ipairs(logoRegistry) do
        if identity.eligibilityRule(context) then
            currentLogoCode = identity.code
            currentLogo = identity.displayIdentifier
            break
        end
    end

    return currentLogoCode, currentLogo
end
