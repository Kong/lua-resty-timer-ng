local utils = require("resty.timer.utils")

local setmetatable = setmetatable
local floor = math.floor

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local assert = utils.assert

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:get_cur_pointer()
    return self.pointer + 1
end


function _M:cal_pointer(pointer, offset)
    assert(pointer >= 1)
    local nelts = self.nelts
    local p = pointer - 1
    local old = p

    p = (p + offset) % nelts

    local cycles = floor(offset / nelts)

    if old + (offset % nelts) >= nelts then
        cycles = cycles + 1
    end

    return p + 1, cycles
end


function _M:insert(pointer, job)
    assert(self.slots)
    assert(pointer > 0)

    local _job = self:get_jobs()[job.name]

    if not _job
        or (_job:is_cancelled() and not _job:is_enabled()) then
        self.slots[pointer][job.name] = job

    else
        return false, "already exists job"
    end

    return true, nil
end


function _M:spin_pointer_one_slot()
    local pointer, cycles = self:cal_pointer(self:get_cur_pointer(), 1)
    self.pointer = pointer - 1
    local higher_wheel = self.higher_wheel

    if higher_wheel then
        for _ = 1, cycles do
            higher_wheel:spin_pointer_one_slot()
        end
    end
end


function _M:get_jobs()
    return self.slots[self:get_cur_pointer()]
end


function _M:get_jobs_by_pointer(pointer)
    return self.slots[pointer]
end


function _M.new(nelts, higher_wheel)
    local self = {
        pointer = 0,

        nelts = nelts,
        slots = utils.table_new(nelts, 0),
        higher_wheel = higher_wheel,
    }

    for i = 1, self.nelts do
        self.slots[i] = setmetatable({ }, { __mode = "v" })
    end

    return setmetatable(self, meta_table)
end


return _M