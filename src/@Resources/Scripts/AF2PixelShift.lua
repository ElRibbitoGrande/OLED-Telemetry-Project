local positions = {
    { 0,  0},
    { 3,  0},
    { 3,  3},
    { 0,  3},
    {-3,  3},
    {-3,  0},
    {-3, -3},
    { 0, -3},
    { 3, -3}
}

local originX = 0
local originY = 0
local positionIndex = 1
local firstUpdate = true

local function moveTo(index)
    local offset = positions[index]
    if not offset then
        return
    end

    positionIndex = index
    SKIN:Bang('!Move', tostring(originX + offset[1]), tostring(originY + offset[2]))
end

function Initialize()
    originX = tonumber(SKIN:GetVariable('AF2PixelShiftOriginX', '2560')) or 2560
    originY = tonumber(SKIN:GetVariable('AF2PixelShiftOriginY', '384')) or 384
    positionIndex = 1
    firstUpdate = true
    moveTo(positionIndex)
end

function Update()
    -- Rainmeter invokes Update once when the measure is initialized. Keep that
    -- first update neutral, then advance once per UpdateDivider interval.
    if firstUpdate then
        firstUpdate = false
        return positionIndex
    end

    positionIndex = (positionIndex % #positions) + 1
    moveTo(positionIndex)
    return positionIndex
end

-- Validation entry point: accepts positions 1..9 without changing the cycle.
function SetPosition(index)
    local requested = tonumber(index)
    if requested and requested >= 1 and requested <= #positions then
        moveTo(math.floor(requested))
    end
end
