local logPath = 'C:\\RainmeterDenon\\Logs\\NowPlayingRainmeter.log'
local maxBytes = 1024 * 1024
local heartbeatSeconds = 30
local lastSignature = nil
local nextHeartbeat = 0
local mismatchActive = false

local function escapeJson(value)
    value = tostring(value or '')
    value = value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', '\\r'):gsub('\n', '\\n')
    return value
end

local function readRawState()
    local file = io.open('C:\\RainmeterDenon\\NowPlaying\\now_playing.txt', 'rb')
    if not file then return '', '', '', '', '' end
    local content = file:read('*a') or ''
    file:close()
    local function field(name)
        return content:match('[\r\n]?' .. name .. '=([^\r\n]*)') or ''
    end
    return field('Active'), field('Source'), field('Title'), field('Artist'), field('Album')
end

local function rotateIfNeeded()
    local file = io.open(logPath, 'rb')
    if not file then return end
    local size = file:seek('end') or 0
    file:close()
    if size < maxBytes then return end
    os.remove(logPath .. '.3')
    os.rename(logPath .. '.2', logPath .. '.3')
    os.rename(logPath .. '.1', logPath .. '.2')
    os.rename(logPath, logPath .. '.1')
end

local function logEvent(eventName, rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist)
    rotateIfNeeded()
    local file = io.open(logPath, 'ab')
    if not file then return end
    local timestamp = os.date('%Y-%m-%dT%H:%M:%S')
    local line = string.format(
        '{"timestamp":"%s","component":"RainmeterAF2","event":"%s","rawActive":"%s","rawSource":"%s","rawTitle":"%s","rawArtist":"%s","rawAlbum":"%s","parsedArtist":"%s"}\r\n',
        timestamp, eventName, escapeJson(rawActive), escapeJson(rawSource), escapeJson(rawTitle),
        escapeJson(rawArtist), escapeJson(rawAlbum), escapeJson(parsedArtist))
    file:write(line)
    file:close()
end

function Initialize()
    nextHeartbeat = os.time()
end

function Update()
    local rawActive, rawSource, rawTitle, rawArtist, rawAlbum = readRawState()
    local measure = SKIN:GetMeasure('DashboardNowPlayingArtist')
    local parsedArtist = measure and measure:GetStringValue() or ''
    local signature = table.concat({rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist}, '|')
    local now = os.time()
    local mismatch = rawArtist ~= parsedArtist

    if mismatch and not mismatchActive then
        logEvent('RAINMETER_MISMATCH', rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist)
    elseif not mismatch and mismatchActive then
        logEvent('RAINMETER_MATCH_RESTORED', rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist)
    elseif signature ~= lastSignature then
        logEvent('RAINMETER_STATE', rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist)
    elseif now >= nextHeartbeat then
        logEvent('RAINMETER_HEARTBEAT', rawActive, rawSource, rawTitle, rawArtist, rawAlbum, parsedArtist)
    end

    mismatchActive = mismatch
    lastSignature = signature
    nextHeartbeat = now + heartbeatSeconds
    return mismatch and 1 or 0
end
