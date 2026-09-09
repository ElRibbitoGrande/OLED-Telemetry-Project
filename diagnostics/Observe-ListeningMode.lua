-- Load through DashboardLogoResolver !CommandMeasure dofile(...).
-- Bounded in-memory observer; preserves the original Update and restores it.
if listeningModeObservationActive then return end
listeningModeObservationActive = true
local originalUpdate = Update
local deadline = os.time() + 180
local path = 'C:\\OLED-Telemetry-Project\\diagnostics\\captures\\rainmeter-listening-mode.tsv'
local last = nil
local sequence = 0
local function value(name)
    local measure = SKIN:GetMeasure(name)
    return measure and (measure:GetStringValue() or '') or '<missing>'
end
function Update()
    local number, text = originalUpdate()
    sequence = sequence + 1
    local fields = {value('DashboardRawListeningMode'), value('DashboardListeningMode'), value('DashboardRawInputSignal')}
    for _, ch in ipairs({'FHL','FHR','FL','C','FR','SL','SR','TRL','TRR','SUB1','SUB2'}) do
        fields[#fields+1] = value('DashboardActive' .. ch)
    end
    local meter = SKIN:GetMeter('AF2ListeningModeValue')
    fields[#fields+1] = meter and meter:GetOption('Text', '') or '<missing>'
    local signature = table.concat(fields, '\t'):gsub('[\r\n]', ' ')
    if signature ~= last then
        local file = io.open(path, 'ab')
        if file then
            file:write(os.date('!%Y-%m-%dT%H:%M:%SZ') .. '\t' .. sequence .. '\t' .. signature .. '\n')
            file:close()
        end
        last = signature
    end
    if os.time() >= deadline then
        Update = originalUpdate
        listeningModeObservationActive = false
    end
    return number, text
end
