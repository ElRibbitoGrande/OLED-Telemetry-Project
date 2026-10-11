local core
local measures = {}
local applied = 1
local previousContext
local function number(name)
    local measure=measures[name]
    return measure and (tonumber(measure:GetValue()) or 0) or 0
end
local function text(name)
    local measure=measures[name]
    return measure and (measure:GetStringValue() or '') or ''
end
function Initialize()
    local ok,module=pcall(dofile,SELF:GetOption('CoreFile'))
    core=ok and module.new() or nil
    if not core then SKIN:Bang('!Log','Adaptive VU core unavailable; using fixed sensitivity.','Error') end
    for _,name in ipairs({'DashboardBox1Clock','DashboardBox1Usable','DashboardLevelSourceCode',
        'DashboardVUEnvelopeLeft','DashboardVUEnvelopeRight',
        'DashboardRawBox1RmsEnvelopeLeft','DashboardRawBox1RmsEnvelopeRight',
        'DashboardNowPlayingActive','DashboardSource','DashboardNowPlayingTitle','DashboardNowPlayingArtist','DashboardNowPlayingAlbum'}) do
        measures[name]=SKIN:GetMeasure(name)
    end
end
function Update()
    if not core then return 1 end
    local box=number('DashboardBox1Usable') == 1
    local windows=number('DashboardLevelSourceCode') == 1 and text('DashboardSource') == 'HTPC'
    local prefix=box and 'DashboardRawBox1RmsEnvelope' or 'DashboardVUEnvelope'
    local calibration=box and (tonumber(SKIN:GetVariable('DashboardBox1CalibrationGain','1')) or 1) or 1
    local base=tonumber(SKIN:GetVariable('DashboardVUGain','2.7')) or 2.7
    local context=text('DashboardSource') .. '\31' .. text('DashboardNowPlayingArtist') .. '\31' .. text('DashboardNowPlayingAlbum') .. '\31' .. text('DashboardNowPlayingTitle')
    local target=core:update(number('DashboardBox1Clock'),number(prefix..'Left')*base*calibration,
        number(prefix..'Right')*base*calibration,(box or windows) and number('DashboardNowPlayingActive') == 1,context)
    if previousContext ~= context then applied=target; previousContext=context end
    -- Interpolate only the slow gain's one-second steps, never the music envelope.
    applied=applied+0.08*(target-applied)
    return applied
end
