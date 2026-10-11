-- Run in Rainmeter's actual Lua runtime through DashboardLogoResolver dofile().
-- Local module/tests only: does not replace any live Update function or measure.
local root='C:\\OLED-Telemetry-Project\\'
local Core=dofile(root..'src\\@Resources\\VU\\AdaptiveGainCore.lua')
local log={}
local function check(condition,message)
    if not condition then error(message) end
    log[#log+1]='PASS: '..message
end
local function run()
    local core=Core.new()
    for frame=0,3000 do
        local level=(frame==1000 or frame==1001) and 3 or 0.4
        core:update(math.floor(frame/25),level,level/2,true,'normal')
    end
    check(core.gainDb==0,'normal program and isolated transient preserve unity gain')
    for frame=0,3000 do core:update(math.floor(frame/25),1.3,0.8,true,'hot') end
    local before=core.gainDb
    check(before<0 and before>=-6,'sustained hot program attenuates within bounds')
    for second=121,421 do core:update(second,0,0,false,'hot') end
    check(core.gainDb==before,'pause and silence freeze sensitivity without wind-up')
    check(core:update(422,0.4,0.2,true,'new-track')==1,'new track starts from baseline instead of inherited attenuation')
    local values={DashboardSource='HTPC',DashboardLevelSourceCode=1,DashboardNowPlayingActive=1,
        DashboardVUEnvelopeLeft=0.5,DashboardVUEnvelopeRight=0.25,DashboardBox1Clock=0}
    local env=setmetatable({SELF={GetOption=function() return root..'src\\@Resources\\VU\\AdaptiveGainCore.lua' end},
        SKIN={GetMeasure=function(_,name) return {GetValue=function() return values[name] or 0 end,
            GetStringValue=function() return values[name] or '' end} end,
            GetVariable=function(_,name,default) return name=='DashboardBox1CalibrationGain' and '1.6' or default end}}, {__index=_G})
    local adapter=assert(loadfile(root..'src\\@Resources\\VU\\AdaptiveGain.lua'))
    setfenv(adapter,env); adapter(); env.Initialize()
    local applied=1
    for frame=0,3000 do
        values.DashboardBox1Clock=math.floor(frame/25)
        local nextGain=env.Update()
        assert(math.abs(nextGain-applied)<0.003,'adapter gain step exceeds smooth bound')
        applied=nextGain
    end
    check(applied<0.8 and applied>0.5,'adapter consumes unclipped HTPC envelope with smooth bounded gain')
    values.DashboardSource='LYR+'; values.DashboardBox1Usable=1
    values.DashboardRawBox1RmsEnvelopeLeft=0.2; values.DashboardRawBox1RmsEnvelopeRight=0.1
    check(env.Update()==1,'adapter resets gain on source transition')
    for frame=3001,6000 do values.DashboardBox1Clock=math.floor(frame/25); applied=env.Update() end
    check(applied==1,'calibrated normal Box1 retains unity adaptive gain')
    local fixtures=dofile(root..'diagnostics\\captures\\adaptive-replay.lua')
    for _,fixture in ipairs(fixtures) do
        local controller=Core.new()
        local pinned,total,maxChange=0,0,0
        local finish=fixture.rows[#fixture.rows][1]
        for _,row in ipairs(fixture.rows) do
            local gain=controller:update(row[1],row[2],row[3],true,fixture.name)
            assert(gain>=0.5-1e-9 and gain<=1,'gain bound violated')
            maxChange=math.max(maxChange,math.abs(gain-1))
            if row[1]>=finish-30 then
                total=total+1
                if math.max(row[2],row[3])*gain>=0.99 then pinned=pinned+1 end
            end
        end
        if fixture.normal then check(maxChange==0,fixture.name..' normal dynamics unchanged')
        else check(pinned/total<0.025,fixture.name..' settled pinning below 2.5%') end
        log[#log+1]=string.format('%s final gain %.3f dB; settled pinning %.3f%%',fixture.name,controller.gainDb,100*pinned/total)
    end
end
local ok,message=pcall(run)
local file=assert(io.open(root..'diagnostics\\captures\\adaptive-test-results.txt','wb'))
file:write(table.concat(log,'\n')..'\n'..(ok and 'ALL PASSED' or 'FAILED: '..tostring(message))..'\n')
file:close()
