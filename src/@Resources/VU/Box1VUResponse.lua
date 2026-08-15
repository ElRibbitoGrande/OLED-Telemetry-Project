local inputMeasure
local output = 0
local attackMs = 85
local decayMs = 520
local gain = 2.7
local updateMs = 32

local function getNumberOption(name, fallback)
    local value = tonumber(SELF:GetOption(name, tostring(fallback)))
    if value == nil then
        return fallback
    end
    return value
end

local function clamp(value)
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function responseAlpha(responseMs)
    if responseMs <= 0 then
        return 1
    end
    return 1 - math.exp(-updateMs / responseMs)
end

function Initialize()
    inputMeasure = SKIN:GetMeasure(SELF:GetOption('InputMeasure', ''))
    attackMs = math.max(0, getNumberOption('AttackMs', 85))
    decayMs = math.max(0, getNumberOption('DecayMs', 520))
    gain = math.max(0, getNumberOption('Gain', 2.7))
    updateMs = math.max(1, getNumberOption('UpdateMs', 32))
    output = 0
end

function Update()
    local target = 0
    if inputMeasure ~= nil then
        target = tonumber(inputMeasure:GetValue()) or 0
    end
    target = clamp(target * gain)

    local responseMs = decayMs
    if target > output then
        responseMs = 0
    end

    output = clamp(output + ((target - output) * responseAlpha(responseMs)))
    return output
end
