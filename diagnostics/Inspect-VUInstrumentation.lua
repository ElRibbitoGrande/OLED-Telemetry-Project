-- Read-only inspection through Rainmeter's existing Lua measure; no Update override.
local skin=SKIN
local marker=skin:GetMeter('DashboardVUVideoSync')
local fields={}
for _,name in ipairs({'DashboardVUComparisonCapture','DashboardVUAdaptiveGain','DashboardVUProbeClock','DashboardVUDisplayLeft','DashboardVUDisplayRight'}) do
    local measure=skin:GetMeasure(name)
    fields[#fields+1]=name..'='..(measure and string.format('%.17g',measure:GetValue()) or 'MISSING')
end
fields[#fields+1]='SyncMeter='..(marker and 'Present' or 'Missing')
fields[#fields+1]='SyncText='..(marker and marker:GetOption('Text','') or '')
local file=assert(io.open('C:\\OLED-Telemetry-Project\\diagnostics\\captures\\VU-instrumentation-state.txt','wb'))
file:write(table.concat(fields,'\n')..'\n');file:close()
