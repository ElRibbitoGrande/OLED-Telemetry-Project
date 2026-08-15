local measures = {}
local rows = {}
local active = false
local stopped = false
local frame = 0
local updateMs = 32
local captureId = nil
local captureDirectory = nil

local function getMeasure(optionName)
    local name = SELF:GetOption(optionName, '')
    if name == '' then
        return nil
    end
    return SKIN:GetMeasure(name)
end

local function getNumber(measure)
    if measure == nil then
        return 0
    end
    return tonumber(measure:GetValue()) or 0
end

local function getString(measure)
    if measure == nil then
        return ''
    end
    return measure:GetStringValue() or ''
end

local function csv(value)
    local text = tostring(value or '')
    if string.find(text, '[,"\r\n]') then
        return '"' .. string.gsub(text, '"', '""') .. '"'
    end
    return text
end

local function readControl(path)
    local file = io.open(path, 'rb')
    if file == nil then
        return nil
    end

    local values = {}
    for line in file:lines() do
        local key, value = string.match(line, '^([^=]+)=(.*)$')
        if key ~= nil then
            values[key] = value
        end
    end
    file:close()

    if values.CaptureId == nil or values.CaptureDirectory == nil then
        return nil
    end
    return values
end

local function writeText(path, content)
    local file, message = io.open(path, 'wb')
    if file == nil then
        return false, message
    end
    file:write(content)
    file:close()
    return true, nil
end

local function completeCapture()
    if stopped or not active then
        return
    end
    stopped = true

    local outputPath = captureDirectory .. '\\rainmeter_comparison.csv'
    local tempPath = outputPath .. '.tmp'
    local ok, message = writeText(tempPath, table.concat(rows, '\r\n') .. '\r\n')
    if ok then
        os.remove(outputPath)
        ok, message = os.rename(tempPath, outputPath)
    end

    if ok then
        writeText(
            captureDirectory .. '\\rainmeter_capture.complete',
            'CaptureId=' .. captureId .. '\r\nFrames=' .. tostring(frame) .. '\r\n'
        )
    else
        writeText(
            captureDirectory .. '\\rainmeter_capture.error.txt',
            tostring(message or 'Unknown Rainmeter capture write failure') .. '\r\n'
        )
    end

    active = false
end

function Initialize()
    measures.windowsLeft = getMeasure('WindowsLeftMeasure')
    measures.windowsRight = getMeasure('WindowsRightMeasure')
    measures.box1LeftRmsDb = getMeasure('Box1LeftRmsDbMeasure')
    measures.box1RightRmsDb = getMeasure('Box1RightRmsDbMeasure')
    measures.box1PreLeft = getMeasure('Box1PreLeftMeasure')
    measures.box1PreRight = getMeasure('Box1PreRightMeasure')
    measures.box1FinalLeft = getMeasure('Box1FinalLeftMeasure')
    measures.box1FinalRight = getMeasure('Box1FinalRightMeasure')
    measures.box1Sequence = getMeasure('Box1SequenceMeasure')
    measures.source = getMeasure('SourceMeasure')
    updateMs = math.max(1, tonumber(SELF:GetOption('UpdateMs', '32')) or 32)

    local control = readControl(SELF:GetOption('ControlFile', ''))
    if control == nil then
        return
    end

    captureId = control.CaptureId
    captureDirectory = control.CaptureDirectory
    rows = {
        'EpochSecond,RainmeterFrame,NominalElapsedMs,Source,WindowsRawLeft,WindowsRawRight,Box1LeftRmsDb,Box1RightRmsDb,Box1PreLeft,Box1PreRight,Box1FinalLeft,Box1FinalRight,Box1Sequence'
    }
    frame = 0
    stopped = false
    active = true
    writeText(
        captureDirectory .. '\\rainmeter_capture.started',
        'CaptureId=' .. captureId .. '\r\n'
    )
end

function Update()
    if not active then
        Initialize()
    end
    if not active then
        return 0
    end

    local fields = {
        tostring(os.time()),
        tostring(frame),
        tostring(frame * updateMs),
        csv(getString(measures.source)),
        string.format('%.17g', getNumber(measures.windowsLeft)),
        string.format('%.17g', getNumber(measures.windowsRight)),
        string.format('%.17g', getNumber(measures.box1LeftRmsDb)),
        string.format('%.17g', getNumber(measures.box1RightRmsDb)),
        string.format('%.17g', getNumber(measures.box1PreLeft)),
        string.format('%.17g', getNumber(measures.box1PreRight)),
        string.format('%.17g', getNumber(measures.box1FinalLeft)),
        string.format('%.17g', getNumber(measures.box1FinalRight)),
        string.format('%.0f', getNumber(measures.box1Sequence))
    }
    rows[#rows + 1] = table.concat(fields, ',')
    frame = frame + 1
    return frame
end

function StopCapture()
    completeCapture()
end

function Finalize()
    completeCapture()
end
