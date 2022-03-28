local utils = require("resty.timer.utils")

local unpack = table.unpack
local concat = table.concat
local debug_getinfo = debug.getinfo
local setmetatable = setmetatable

local max = math.max
local min = math.min
local floor = math.floor
local modf = math.modf
local huge = math.huge

local pcall = pcall

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local now = ngx.now

local assert = utils.assert

local _M = {}


local function job_tostring(job)
    local stats = job.stats
    local offset = job.offset
    local next_pointer = job.next_pointer
    local runtime = stats.runtime
    local meta = job.meta

    local tbl = {
        "name = ",                  tostring(job.name),
        ", enable = ",              tostring(job._enable),
        ", cancel = ",              tostring(job._cancel),
        ", once = ",                tostring(job._once),
        ", offset.hour = ",         tostring(offset.hour),
        ", offset.minute = ",       tostring(offset.minute),
        ", offset.second = ",       tostring(offset.second),
        ", next.hour = ",           tostring(next_pointer.hour),
        ", next.minute = ",         tostring(next_pointer.minute),
        ", next.second = ",         tostring(next_pointer.second),
        ", next.msec = ",           tostring(next_pointer.msec),
        ", runtime.max = ",         tostring(runtime.max),
        ", runtime.min = ",         tostring(runtime.min),
        ", runtime.avg = ",         tostring(runtime.avg),
        ", runtime.variance = ",    tostring(runtime.variance),
        ", meta.name = ",           tostring(meta.name),
    }

    return concat(tbl)
end


local meta_table = {
    __index = _M,
    __tostring = job_tostring,
}


local function job_create_meta(job)
    local meta = job.meta
    local callstack = meta.callstack
    local base = 4

    for i = 1, 3 do
        local info = debug_getinfo(i + base, "nSl")

        if not info or info.short_src == "[C]" then
            break
        end

        callstack[i] = {
            line = info.currentline,
            func = info.name or info.what,
            source = info.short_src,
        }
    end

    local top_stack = callstack[1]

    if top_stack then
        -- like `init.lua:128:start_timer()`
        meta.name = top_stack.source .. ":" .. top_stack.line .. ":"
            .. top_stack.func .. "()"
    end
end


-- Calculate the position of each pointer when the job expires
local function job_re_cal_next_pointer(job, wheels)
    local offset_hour = job.offset.hour
    local offset_minute = job.offset.minute
    local offset_second = job.offset.second
    local offset_msec = job.offset.msec

    local hour_wheel = wheels.hour_wheel
    local minute_wheel = wheels.minute_wheel
    local second_wheel = wheels.second_wheel
    local msec_wheel = wheels.msec_wheel

    local cur_hour_pointer = hour_wheel:get_cur_pointer()
    local cur_minute_pointer = minute_wheel:get_cur_pointer()
    local cur_second_pointer = second_wheel:get_cur_pointer()
    local cur_msec_pointer = msec_wheel:get_cur_pointer()

    local next_hour_pointer = 0
    local next_minute_pointer = 0
    local next_second_pointer = 0
    local next_msec_pointer = 0

    local is_spin_to_start_slot = false

    if offset_msec~= 0 then
        next_msec_pointer, is_spin_to_start_slot =
            msec_wheel:cal_pointer(cur_msec_pointer, offset_msec)
    end

    if offset_second~= 0 or is_spin_to_start_slot then

        -- Suppose the current pointer of the `msec_wheel` points to slot 7
        -- and the `msec_wheel` has ten slots.
        -- `offset_msec = 4`, which results in 1 at this point,
        -- but obviously we need to make
        -- the pointer of the `minute_wheel` spin, like a clock.
        -- Same for `offset_minute` and `offset_hour`.
        if is_spin_to_start_slot then
            offset_second = offset_second + 1
        end

        next_second_pointer, is_spin_to_start_slot =
            second_wheel:cal_pointer(cur_second_pointer, offset_second)

    else
        is_spin_to_start_slot = false
    end

    if offset_minute~= 0 or is_spin_to_start_slot then
        if is_spin_to_start_slot then
            offset_minute = offset_minute + 1
        end

        next_minute_pointer, is_spin_to_start_slot =
            minute_wheel:cal_pointer(cur_minute_pointer, offset_minute)

    else
        is_spin_to_start_slot = false
    end

    if offset_hour~= 0 or is_spin_to_start_slot then
        if is_spin_to_start_slot then
            offset_hour = offset_hour + 1
        end

        next_hour_pointer, _ =
            hour_wheel:cal_pointer(cur_hour_pointer, offset_hour)
    end


    -- Suppose a job will expire in one minute
    -- and we need to spin the pointer of the `minute_wheel`,
    -- but obviously we should not make the
    -- second and msec pointer pointing to zero,
    -- they should point to the current position.

    if next_hour_pointer ~= 0 then
        if next_minute_pointer == 0 then
            next_minute_pointer = cur_minute_pointer
        end

        if next_second_pointer == 0 then
            next_second_pointer = cur_second_pointer
        end

        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end

    elseif next_minute_pointer ~= 0 then
        if next_second_pointer == 0 then
            next_second_pointer = cur_second_pointer
        end

        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end

    elseif next_second_pointer ~= 0 then
        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end
    end


    assert(next_hour_pointer ~= 0 or
           next_minute_pointer ~= 0 or
           next_second_pointer ~= 0 or
           next_msec_pointer ~= 0, "unexpected error")

    job.next_pointer.hour = next_hour_pointer
    job.next_pointer.minute = next_minute_pointer
    job.next_pointer.second = next_second_pointer
    job.next_pointer.msec = next_msec_pointer
end


function _M:pause()
    self._enable = false
end


function _M:cancel()
    self._enable = false
    self._cancel = true
end


function _M:enable()
    self._enable = true
    self._cancel = false
end


function _M:is_enable()
    return self._enable
end


function _M:is_once()
    return self._once
end


function _M:is_runable()
    return self._enable and not self._cancel and not self._running
end


function _M:is_immediately()
    return self._immediately
end


function _M:re_cal_next_pointer(wheels)
    job_re_cal_next_pointer(self, wheels)
end


function _M.new(wheels, name, callback, delay, once, args)
    local delay_origin = delay
    local offset_hour, offset_minute, offset_second, offset_msec
    local immediately = true

    if delay ~= 0 then
        immediately = false

        delay, offset_msec = modf(delay)
        offset_msec = offset_msec * 1000 + 10
        offset_msec = floor(floor(offset_msec) / 100)
        offset_msec = min(offset_msec, 9)

        offset_hour = modf(delay / 60 / 60)
        delay = delay % (60 * 60)

        offset_minute = modf(delay / 60)
        offset_second = delay % 60
    end



    local self = {
        _enable = true,
        _cancel = false,
        _running = false,
        _immediately = immediately,
        name = name,
        callback = callback,
        delay = delay_origin,
        offset = {
            hour = offset_hour,
            minute = offset_minute,
            second = offset_second,
            msec = offset_msec,
        },
        next_pointer = {
            hour = 0,
            minute = 0,
            second = 0,
            msec = 0,
        },
        _once = once,
        args = args,
        stats = {
            runtime = {
                avg = 0,
                max = -1,
                min = huge,
                variance = 0,
            },

            runs = 0,
            finish = 0,
            last_err_msg = "",
        },
        meta = {
            name = "[C]",
            callstack = {},
        },
    }

    job_create_meta(self)

    if not immediately then
        job_re_cal_next_pointer(self, wheels)
    end

    return setmetatable(self, meta_table)
end


function _M:execute()
    local stats = self.stats
    local runtime = stats.runtime
    stats.runs = stats.runs + 1
    local start = now()

    if not self:is_runable() then
        return
    end

    self._running = true

    local ok, err = pcall(self.callback, false, unpack(self.args))

    local finish = stats.finish

    if ok then
        finish = finish + 1

    else
        stats.last_err_msg = err
    end

    self._running = false
    stats.finish = finish

    local spend = now() - start

    runtime.max = max(runtime.max, spend)
    runtime.min = min(runtime.min, spend)

    local old_avg = runtime.avg
    runtime.avg = utils.get_avg(spend, finish, old_avg)

    local old_variance = runtime.variance
    runtime.variance = utils.get_variance(spend, finish, old_variance, old_avg)

end


return _M