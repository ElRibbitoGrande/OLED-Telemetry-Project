-- Slow stereo-linked attenuation. No needle-envelope filtering occurs here.
local Core = {}
Core.__index = Core

function Core.new()
    return setmetatable({gainDb=0, targetDb=0, buckets={}, samples={}, second=nil, context=nil}, Core)
end

function Core:update(second, left, right, active, context)
    if self.context ~= context then
        self.gainDb, self.targetDb = 0, 0
        self.buckets, self.samples, self.second = {}, {}, nil
        self.context = context
    end
    local linked = math.max(left, right)
    if not active or linked ~= linked or linked < 0.01 then
        -- Discard the window on pause/silence; preserve sensitivity, never wind up.
        self.buckets, self.samples, self.second = {}, {}, second
        return 10^(self.gainDb/20)
    end
    if self.second == nil then self.second = second end
    if second ~= self.second then
        local elapsed = second-self.second
        if elapsed < 0 or elapsed > 2 then
            self.buckets, self.samples = {}, {}
            elapsed = 0
        end
        if #self.samples > 0 then
            self.buckets[#self.buckets+1] = self.samples
            if #self.buckets > 20 then table.remove(self.buckets,1) end
        end
        self.samples = {}
        if #self.buckets == 20 then
            local recent, high = {}, 0
            local gain = 10^(self.gainDb/20)
            for _, bucket in ipairs(self.buckets) do
                for _, value in ipairs(bucket) do
                    recent[#recent+1] = value
                    if value*gain >= 0.99 then high = high+1 end
                end
            end
            -- Captured normal material pinned 0--2.5%; hot HTPC pinned 41%.
            if high/#recent >= 0.10 then
                table.sort(recent)
                local p = (#recent-1)*0.95+1
                local lo,hi = math.floor(p),math.ceil(p)
                local level = recent[lo]+(recent[hi]-recent[lo])*(p-lo)
                self.targetDb = math.min(self.targetDb, math.max(-6,20*math.log(0.90/level)/math.log(10)))
            end
        end
        self.gainDb = math.max(self.targetDb,self.gainDb-0.15*elapsed)
        self.second = second
    end
    if #self.samples < 256 then self.samples[#self.samples+1] = linked end
    return 10^(self.gainDb/20)
end

return Core
