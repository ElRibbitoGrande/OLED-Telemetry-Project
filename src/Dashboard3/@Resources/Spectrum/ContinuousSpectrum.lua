local bands = {}

local leftX = 390
local rightX = 1985
local baselineY = 1220
local topY = 300

local bandCount = 32
local subdivisions = 8

local weights = {
    0.55, 0.58, 0.62, 0.66, 0.70, 0.74, 0.78, 0.82,
    0.88, 0.94, 1.00, 1.06, 1.12, 1.18, 1.24, 1.30,
    1.36, 1.42, 1.48, 1.54, 1.60, 1.66, 1.72, 1.78,
    1.84, 1.90, 1.96, 2.02, 2.08, 2.14, 2.20, 2.26
}

function Initialize()
    for i = 1, bandCount do
        local name = "MeasureBand" .. string.format("%02d", i)
        bands[i] = SKIN:GetMeasure(name)
    end
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end

    return value
end

local function catmullRom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t

    return 0.5 * (
        (2 * p1)
        + (-p0 + p2) * t
        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

local function smooth(values)
    local result = {}

    for i = 1, bandCount do
        local previous = values[math.max(1, i - 1)]
        local current = values[i]
        local following = values[math.min(bandCount, i + 1)]

        result[i] = previous * 0.22
            + current * 0.56
            + following * 0.22
    end

    return result
end

function Update()
    local values = {}

    for i = 1, bandCount do
        local raw = 0

        if bands[i] then
            raw = tonumber(bands[i]:GetValue()) or 0
        end

        raw = math.max(0, raw)

        -- Compress quiet information upward without a hard maximum plateau.
        local weighted = (raw ^ 0.58) * weights[i]
        local softened = 1 - math.exp(-weighted * 1.30)

        -- Keep the outer ends subordinate to Now Playing and Volume.
        local position = (i - 1) / (bandCount - 1)
        local envelope = 0.22 + 0.78 * (math.sin(math.pi * position) ^ 0.48)

        values[i] = softened * envelope
    end

    -- Two gentle smoothing passes remove isolated spikes without killing motion.
    values = smooth(values)
    values = smooth(values)

    local width = rightX - leftX
    local step = width / (bandCount - 1)
    local usableHeight = baselineY - topY

    local path = string.format("%.1f,%.1f", leftX, baselineY)

    for i = 1, bandCount - 1 do
        local p0 = values[math.max(1, i - 1)]
        local p1 = values[i]
        local p2 = values[i + 1]
        local p3 = values[math.min(bandCount, i + 2)]

        for segment = 0, subdivisions - 1 do
            local t = segment / subdivisions
            local interpolated = catmullRom(p0, p1, p2, p3, t)
            interpolated = clamp(interpolated, 0, 0.96)

            local x = leftX + ((i - 1 + t) * step)
            local y = baselineY - (interpolated * usableHeight)

            path = path .. string.format(
                " | LineTo %.1f,%.1f",
                x,
                y
            )
        end
    end

    local finalValue = clamp(values[bandCount], 0, 0.96)

    path = path
        .. string.format(
            " | LineTo %.1f,%.1f",
            rightX,
            baselineY - (finalValue * usableHeight)
        )
        .. string.format(
            " | LineTo %.1f,%.1f",
            rightX,
            baselineY
        )
        .. " | ClosePath 1"

    return path
end