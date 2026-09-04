local statePath = 'C:\\RainmeterDenon\\NowPlaying\\now_playing.txt'
local logPath = 'C:\\RainmeterDenon\\Logs\\NowPlayingRainmeter.log'
local statusPath = 'C:\\RainmeterDenon\\NowPlaying\\rainmeter_artwork_state.txt'
local maxBytes = 1024 * 1024
local heartbeatSeconds = 60
local reapplySeconds = 30

local lastSignature = nil
local lastValidState = nil
local appliedArtwork = ''
local nextHeartbeat = 0
local nextReapply = 0
local readFailureActive = false
local artworkFailureActive = false

local function measureString(name)
    local measure = SKIN:GetMeasure(name)
    if measure == nil then return '' end
    return measure:GetStringValue() or ''
end

local function meterOption(name, option)
    local meter = SKIN:GetMeter(name)
    if meter == nil then return '' end
    return meter:GetOption(option, '') or ''
end

local function escapeJson(value)
    value = tostring(value or '')
    return value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', '\\r'):gsub('\n', '\\n')
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

local function logEvent(eventName, state, detail)
    rotateIfNeeded()
    local file = io.open(logPath, 'ab')
    if not file then return end
    state = state or {}
    local line = string.format(
        '{"timestamp":"%s","component":"RainmeterAF2","event":"%s","active":"%s","playbackStatus":"%s","source":"%s","title":"%s","artist":"%s","album":"%s","artworkAvailable":"%s","artwork":"%s","parsedArtwork":"%s","appliedArtwork":"%s","meterImageName":"%s","meterHidden":"%s","detail":"%s"}\r\n',
        os.date('%Y-%m-%dT%H:%M:%S'), escapeJson(eventName), escapeJson(state.Active),
        escapeJson(state.PlaybackStatus), escapeJson(state.Source), escapeJson(state.Title), escapeJson(state.Artist),
        escapeJson(state.Album), escapeJson(state.ArtworkAvailable), escapeJson(state.Artwork),
        escapeJson(measureString('DashboardArtwork')), escapeJson(appliedArtwork),
        escapeJson(meterOption('AF2Artwork', 'ImageName')),
        escapeJson(meterOption('AF2Artwork', 'Hidden')), escapeJson(detail))
    file:write(line)
    file:close()
end

local function readState()
    local file = io.open(statePath, 'rb')
    if not file then return nil, 'open failed' end
    local content = file:read('*a') or ''
    file:close()

    local state = {}
    for _, name in ipairs({
        'Active', 'Source', 'Title', 'Artist', 'Album', 'PositionSeconds',
        'DurationSeconds', 'Position', 'Duration', 'Progress',
        'ArtworkAvailable', 'Artwork', 'Updated', 'PlaybackStatus'
    }) do
        state[name] = content:match('^' .. name .. '=([^\r\n]*)')
            or content:match('[\r\n]' .. name .. '=([^\r\n]*)')
    end

    if state.Active == nil or state.ArtworkAvailable == nil or state.Artwork == nil then
        return nil, 'required fields missing'
    end
    if not state.Active:match('^[01]$') or not state.ArtworkAvailable:match('^[01]$') then
        return nil, 'required fields invalid'
    end
    return state, nil
end

local function artworkFileSize(path)
    if path == nil or path == '' then return nil end
    local file = io.open(path, 'rb')
    if not file then return nil end
    local size = file:seek('end')
    file:close()
    return size
end

local function writeStatus(state, fileSize, action)
    local file = io.open(statusPath, 'wb')
    if not file then return end
    file:write('Captured=' .. os.date('%Y-%m-%dT%H:%M:%S') .. '\r\n')
    file:write('Active=' .. tostring(state.Active or '') .. '\r\n')
    file:write('PlaybackStatus=' .. tostring(state.PlaybackStatus or '') .. '\r\n')
    file:write('Source=' .. tostring(state.Source or '') .. '\r\n')
    file:write('Title=' .. tostring(state.Title or '') .. '\r\n')
    file:write('Artist=' .. tostring(state.Artist or '') .. '\r\n')
    file:write('Album=' .. tostring(state.Album or '') .. '\r\n')
    file:write('ArtworkAvailable=' .. tostring(state.ArtworkAvailable or '') .. '\r\n')
    file:write('AdvertisedArtwork=' .. tostring(state.Artwork or '') .. '\r\n')
    file:write('ParsedDashboardArtwork=' .. measureString('DashboardArtwork') .. '\r\n')
    file:write('AppliedArtwork=' .. tostring(appliedArtwork or '') .. '\r\n')
    file:write('MeterImageName=' .. meterOption('AF2Artwork', 'ImageName') .. '\r\n')
    file:write('MeterHidden=' .. meterOption('AF2Artwork', 'Hidden') .. '\r\n')
    file:write('ArtworkFileSize=' .. tostring(fileSize or '') .. '\r\n')
    file:write('Action=' .. tostring(action or '') .. '\r\n')
    file:close()
end

local function applyArtwork(state, fileSize, reason)
    if SKIN:GetMeter('AF2Artwork') == nil then return end
    -- Force Rainmeter to release any stale cached bitmap before loading the
    -- complete, validated file. This targets one meter and never refreshes a skin.
    SKIN:Bang('!SetOption', 'AF2Artwork', 'ImageName', '')
    SKIN:Bang('!UpdateMeter', 'AF2Artwork')
    appliedArtwork = state.Artwork
    SKIN:Bang('!SetOption', 'AF2Artwork', 'ImageName', appliedArtwork)
    SKIN:Bang('!UpdateMeter', 'AF2Artwork')
    SKIN:Bang('!ShowMeter', 'AF2Artwork')
    SKIN:Bang('!Redraw')
    writeStatus(state, fileSize, reason)
end

local function hideArtwork(state, reason)
    if SKIN:GetMeter('AF2Artwork') == nil then return end
    appliedArtwork = ''
    SKIN:Bang('!HideMeter', 'AF2Artwork')
    SKIN:Bang('!Redraw')
    writeStatus(state, nil, reason)
end

function Initialize()
    nextHeartbeat = os.time()
    nextReapply = os.time()
end

function Update()
    local now = os.time()
    local state, readError = readState()
    if state == nil then
        if not readFailureActive then
            logEvent('STATE_READ_TRANSIENT_FAILURE', lastValidState, readError)
            readFailureActive = true
        end
        return 0
    end

    if readFailureActive then
        logEvent('STATE_READ_RECOVERED', state, '')
        readFailureActive = false
    end
    lastValidState = state

    local signature = table.concat({
        state.Active or '', state.PlaybackStatus or '', state.Source or '', state.Title or '', state.Artist or '',
        state.Album or '', state.ArtworkAvailable or '', state.Artwork or ''
    }, '|')
    local changed = signature ~= lastSignature
    local fileSize = artworkFileSize(state.Artwork)
    local shouldDisplay = state.Active == '1' and state.ArtworkAvailable == '1'
        and state.Artwork ~= '' and fileSize ~= nil and fileSize > 1024

    if shouldDisplay then
        if artworkFailureActive then
            logEvent('ARTWORK_FILE_RECOVERED', state, 'size=' .. tostring(fileSize))
            artworkFailureActive = false
        end
        if changed or appliedArtwork ~= state.Artwork then
            applyArtwork(state, fileSize, 'state transition')
            logEvent('ARTWORK_APPLIED', state, 'size=' .. tostring(fileSize))
            nextReapply = now + reapplySeconds
        elseif now >= nextReapply then
            applyArtwork(state, fileSize, 'targeted self-heal')
            logEvent('ARTWORK_TARGETED_REAPPLY', state, 'size=' .. tostring(fileSize))
            nextReapply = now + reapplySeconds
        end
    elseif state.Active == '1' and state.ArtworkAvailable == '1' and state.Artwork ~= '' then
        if not artworkFailureActive then
            logEvent('ARTWORK_FILE_UNAVAILABLE', state, 'advertised file is missing, unreadable, or too small')
            artworkFailureActive = true
        end
        -- Keep the last successfully applied image through a transient file failure.
    elseif changed then
        hideArtwork(state, 'valid state no longer advertises artwork')
        logEvent('ARTWORK_HIDDEN', state, '')
    end

    if changed then
        logEvent('RAINMETER_STATE', state, '')
        lastSignature = signature
    elseif now >= nextHeartbeat then
        logEvent('RAINMETER_HEARTBEAT', state, 'artworkFileSize=' .. tostring(fileSize or ''))
        nextHeartbeat = now + heartbeatSeconds
    end
    return 0
end
