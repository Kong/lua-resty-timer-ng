local utils = require("resty.timer.utils")

local setmetatable = setmetatable
local floor = math.floor

local table_insert = table.insert
local table_unpack = table.unpack

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

    local cycles = floor(offset / nelts)

    if old + (offset % nelts) >= nelts then
        cycles = cycles + 1
    end

    return p + 1, cycles
end


function _M:cal_pointer_cascade(pointers, offsets)
    local _pointers = {}
    local wheel = self
    local cycles = 0
    for i = 1, #pointers do
        assert(offsets[i] ~= nil, "unexpected error")
        assert(wheel ~= nil, "unexpected error")

        local p

        if offsets[i] == 0 and cycles == 0 then
            p = 0
            cycles = 0

        else
            p, cycles = wheel:cal_pointer(pointers[i], offsets[i] + cycles)
        end

        table_insert(_pointers, p)

        wheel = wheel.higher_wheel
    end

    return table_unpack(_pointers)
end


function _M:insert(job)
    assert(self.slots)

    local next_pointer = job:get_next_pointer(self.id)

    if next_pointer ~= 0 then
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
    local ret = self.expired_jobs
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