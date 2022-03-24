local unpack = table.unpack
local debug_getinfo = debug.getinfo

local max = math.max
local min = math.min
local floor = math.floor
local modf = math.modf
local huge = math.huge

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local now = ngx.now

local utils = require("resty.timer.utils")

local _M = {}


local function job_tostring(job)
    local str = ""

    local stats = job.stats
    local delay = job.delay
    local next_pointer = job.next_pointer
    local runtime = stats.runtime
    local meta = job.meta

    str = str .. "name = " .. job.name
    str = str .. ", enable = " .. tostring(job._enable)
    str = str .. ", cancel = " .. tostring(job._cancel)
    str = str .. ", delay.hour = " .. tostring(delay.hour)
    str = str .. ", delay.minute = " .. tostring(delay.minute)
    str = str .. ", delay.second = " .. tostring(delay.second)
    str = str .. ", delay.msec = " .. tostring(delay.msec)
    str = str .. ", next.hour = " .. tostring(next_pointer.hour)
    str = str .. ", next.minute = " .. tostring(next_pointer.minute)
    str = str .. ", next.second = " .. tostring(next_pointer.second)
    str = str .. ", next.msec = " .. tostring(next_pointer.msec)
    str = str .. ", runtime.max = " .. runtime.max
    str = str .. ", runtime.min = " .. runtime.min
    str = str .. ", runtime.avg = " .. runtime.avg
    str = str .. ", runtime.variance = " .. runtime.variance
    str = str .. ", meta.name = " .. meta.name

    return str
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


local function job_re_cal_next_pointer(job, wheels)
    local _

    local delay_hour = job.delay.hour
    local delay_minute = job.delay.minute
    local delay_second = job.delay.second
    local delay_msec = job.delay.msec

    local hour_wheel = wheels.hour
    local minute_wheel = wheels.min
    local second_wheel = wheels.sec
    local msec_wheel = wheels.msec

    local cur_hour_pointer = hour_wheel:get_cur_pointer()
    local cur_minute_pointer = minute_wheel:get_cur_pointer()
    local cur_second_pointer = second_wheel:get_cur_pointer()
    local cur_msec_pointer = msec_wheel:get_cur_pointer()

    local next_hour_pointer = 0
    local next_minute_pointer = 0
    local next_second_pointer = 0
    local next_msec_pointer = 0

    local up = false

    if delay_msec then
        next_msec_pointer, up =
            msec_wheel:cal_pointer(cur_msec_pointer, delay_msec)
    end

    if delay_second or up then

        if not delay_second then
            delay_second = 0
        end

        if up then
            delay_second = delay_second + 1
        end

        next_second_pointer, up =
            second_wheel:cal_pointer(cur_second_pointer, delay_second)

    else
        up = false
    end

    if delay_minute or up then

        if not delay_minute then
            delay_minute = 0
        end

        if up then
            delay_minute = delay_minute + 1
        end

        next_minute_pointer, up =
            minute_wheel:cal_pointer(cur_minute_pointer, delay_minute)

    else
        up = false
    end

    if delay_hour or up then

        if not delay_hour then
            delay_hour = 0
        end

        if up then
            delay_hour = delay_hour + 1
        end

        next_hour_pointer, _ =
            hour_wheel:cal_pointer(cur_hour_pointer, delay_hour)
    end

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
    local delay_hour, delay_minute, delay_second, delay_msec
    local immediately = false

    if delay ~= 0 then
        delay, delay_msec = modf(delay)
        delay_msec = delay_msec * 1000 + 10
        delay_msec = floor(delay_msec)
        delay_msec = floor(delay_msec / 100)

        delay_hour = modf(delay / 60 / 60)
        delay = delay % (60 * 60)

        delay_minute = modf(delay / 60)
        delay_second = delay % 60

        if delay_msec == 10 then
            delay_second = delay_second + 1
            delay_msec = nil
        end

        if delay_second == 0 then
            if delay_hour == 0 and delay_minute == 0 then
                delay_second = nil
            end
        end

        if delay_minute == 0 then
            if delay_hour == 0 then
                delay_minute = nil
            end
        end

        if delay_hour == 0 then
            delay_hour = nil
        end

    else
        immediately = true
    end



    local self = {
        _enable = true,
        _cancel = false,
        _running = false,
        _immediately = immediately,
        name = name,
        callback = callback,
        delay = {
            origin = delay_origin,
            hour = delay_hour,
            minute = delay_minute,
            second = delay_second,
            msec = delay_msec,
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