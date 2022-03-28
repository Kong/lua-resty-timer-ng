local utils = require("resty.timer.utils")

local setmetatable = setmetatable

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
    return self.pointer
end


function _M:cal_pointer(pointer, offset)
    local nelts = self.nelts
    local is_spin_to_start_slot = false
    local p = pointer
    local old = p

    p = (p + offset) % (nelts + 1)

    if old + offset > nelts then
        is_spin_to_start_slot = true

        -- example: (3 + 5) % 8 = 0
        -- but the index of the first slot of the wheel is 1
        -- so `+ 1`
        p = p + 1
    end

    return p, is_spin_to_start_slot
end


function _M:insert(pointer, job)
    assert(self.slots)
    assert(pointer > 0)

    local _job = self.slots[pointer][job.name]

    if not _job or not _job:is_runable() then
        self.slots[pointer][job.name] = job

    else
        return false, "already exists job"
    end

    return true, nil
end


function _M:spin_pointer_one_slot()
    local pointer, is_spin_to_start_slot = self:cal_pointer(self.pointer, 1)
    self.pointer = pointer

    return self.slots[self.pointer], is_spin_to_start_slot
end


function _M:get_jobs()
    return self.slots[self.pointer]
end


function _M:get_jobs_by_pointer(pointer)
    return self.slots[pointer]
end


function _M.new(nelts)
    local self = {
        pointer = 1,
        nelts = nelts,
        slots = {},
    }

    for i = 1, self.nelts do
        self.slots[i] = setmetatable({ }, { __mode = "v" })
    end

    return setmetatable(self, meta_table)
end


return _M