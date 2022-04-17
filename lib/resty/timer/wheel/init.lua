local utils = require("resty.timer.utils")

local math_floor = math.floor

local ngx = ngx

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
-- luacheck: pop

local setmetatable = setmetatable

local assert = utils.assert

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:set_higher_wheel(wheel)
    self.higher_wheel = wheel
end

function _M:set_lower_wheel(wheel)
    self.lower_wheel = wheel
end

function _M:get_cur_pointer()
    return self.pointer + 1
end


function _M:cal_pointer(pointer, offset)
    assert(pointer >= 1)
    local nelts = self.nelts
    local p = pointer - 1
    local old = p

    p = (p + offset) % nelts

    local cycles = math_floor(offset / nelts)

    if old + (offset % nelts) >= nelts then
        cycles = cycles + 1
    end

    return p + 1, cycles
end


function _M:cal_pointer_cascade(steps)
    local next_pointers = { }
    local cur_wheel = self

    local steps_for_cur_wheel = steps
    local steps_for_next_wheel

    repeat
        local pointer

        pointer, steps_for_next_wheel =
        cur_wheel:cal_pointer(cur_wheel:get_cur_pointer(),
                              steps_for_cur_wheel)

        next_pointers[cur_wheel.id] = pointer

        steps_for_cur_wheel = steps_for_next_wheel
        cur_wheel = cur_wheel.higher_wheel
    until not cur_wheel or steps_for_cur_wheel == 0

    return next_pointers
end


function _M:insert(job)
    assert(self.slots)

    local next_pointer = job:get_next_pointer(self.id)

    if next_pointer then
        local _job = self:get_jobs_by_pointer(next_pointer)[job.name]

        if not _job
           or (_job:is_cancelled() and not _job:is_enabled()) then

            self.slots[next_pointer][job.name] = job

        else
            return false, "already exists job"
        end

        return true, nil
    end

    local lower_wheel = self.lower_wheel

    if lower_wheel then
        return lower_wheel:insert(job)
    end

    self.expired_jobs[job.name] = job

    return true, nil
end


function _M:spin_pointer(offset)
    assert(offset >= 0)

    if offset == 0 then
        return
    end

    local final_pointer = self:get_cur_pointer()
    local cycles
    local higher_wheel = self.higher_wheel
    local lower_wheel = self.lower_wheel
    local expired_jobs = self.expired_jobs

    for _ = 1, offset do
        final_pointer, cycles = self:cal_pointer(final_pointer, 1)

        if higher_wheel then
            higher_wheel:spin_pointer(cycles)
        end

        local jobs = self:get_jobs_by_pointer(final_pointer)

        for name, job in pairs(jobs) do
            jobs[name] = nil

            if lower_wheel then
                lower_wheel:insert(job)
                goto continue
            end

            expired_jobs[name] = job

            ::continue::
        end

    end

    self.pointer = final_pointer - 1
end


function _M:get_jobs()
    return self.slots[self:get_cur_pointer()]
end


function _M:get_jobs_by_pointer(pointer)
    return self.slots[pointer]
end


function _M:fetch_all_expired_jobs()
    if utils.table_is_empty(self.expired_jobs) then
        return nil
    end

    local ret = self.expired_jobs

    -- TODO: GC pressure
    self.expired_jobs = {}

    return ret
end


function _M.new(id, nelts)
    assert(id ~= nil)

    local self = {
        id = id,

        pointer = 0,

        nelts = nelts,
        slots = utils.table_new(nelts, 0),
        higher_wheel = nil,
        lower_wheel = nil,

        expired_jobs = {},
    }

    for i = 1, self.nelts do
        self.slots[i] = setmetatable({ }, { __mode = "v" })
    end

    return setmetatable(self, meta_table)
end


return _M