-- Direct health-file reader: independent of the source WebParser and logo resolver.
local healthPath = 'C:\\RainmeterDenon\\avr_health_display.txt'
local ackPath = 'C:\\RainmeterDenon\\avr_presentation_ack.txt'
local valid = false
local reset = false
local lastAck = 0
local values = {'AF2SourceValue','AF2ListeningModeValue','AF2VolumeValue',
    'AF2QuickSelectValue','AF2FormatValue','AF2RLOValue'}
local logos = {'AF2LogoAtmos','AF2LogoDTSX','AF2LogoSchiit','AF2LogoApple','AF2LogoPlex','AF2LogoWindows'}
local function readFields(path)
    local file = io.open(path, 'rb')
    if not file then return {} end
    local result = {}
    for line in file:lines() do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then result[key] = value:gsub('\r$', '') end
    end
    file:close()
    return result
end
local function measure(name)
    local item = SKIN:GetMeasure(name)
    return item and item:GetStringValue() or ''
end
function Initialize()
    valid = false
    reset = false
end
function Update()
    local state = readFields(healthPath)
    local now = os.time()
    local age = now - (tonumber(state.Epoch) or 0)
    local current = age >= -2 and age < 10
    valid = current and state.Trusted == '1'
    reset = current and state.ResetAvr == '1'
    -- Reapply each second: frozen source controls cannot cover the warning.
    for _, name in ipairs(values) do
        SKIN:Bang(valid and '!ShowMeter' or '!HideMeter', name)
    end
    for _, channel in ipairs({'FHL','FHR','FL','C','FR','SL','SR','TRL','TRR'}) do
        local active = valid and state.ChannelsFresh == '1' and tonumber(measure('DashboardActive' .. channel)) == 1
        SKIN:Bang(active and '!ShowMeter' or '!HideMeter', 'AF2' .. channel)
    end
    if not valid then
        for _, name in ipairs(logos) do SKIN:Bang('!HideMeter', name) end
        for _, side in ipairs({'Left','Right'}) do
            SKIN:Bang('!HideMeter', 'AF2VUNeedle' .. side)
            SKIN:Bang('!HideMeter', 'AF2VUShadow' .. side)
        end
    else
        for _, side in ipairs({'Left','Right'}) do
            SKIN:Bang('!ShowMeter', 'AF2VUNeedle' .. side)
            SKIN:Bang('!ShowMeter', 'AF2VUShadow' .. side)
        end
        local code = tonumber(measure('DashboardCurrentLogoCode')) or 0
        for index, name in ipairs(logos) do
            SKIN:Bang(index == code and '!ShowMeter' or '!HideMeter', name)
        end
    end
    SKIN:Bang(reset and '!ShowMeterGroup' or '!HideMeterGroup', 'AF2AvrWarning')
    SKIN:Bang('!Redraw')
    if now ~= lastAck then
        lastAck = now
        local file = io.open(ackPath .. '.tmp', 'wb')
        if file then
            file:write('Epoch=' .. now .. '\nSession=' .. (state.Session or '') ..
                '\nSource=' .. measure('DashboardRawSource') ..
                '\nMode=' .. measure('DashboardRawListeningMode') ..
                '\nVolume=' .. measure('DashboardRawVolume') ..
                '\nWarningHidden=' .. tostring(SKIN:GetMeter('AF2AvrWarningTitle'):GetOption('Hidden','1')) .. '\n')
            file:close()
            os.remove(ackPath)
            os.rename(ackPath .. '.tmp', ackPath)
        end
    end
    return valid and 1 or 0
end
