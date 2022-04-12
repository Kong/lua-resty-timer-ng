local utils = require("resty.timer.utils")
local constants = require("resty.timer.constants")

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
    local elapsed_time = stats.elapsed_time
    local meta = job.meta

    local tbl = {
        "name = ",                      tostring(job.name),
        ", enable = ",                  tostring(job._enable),
        ", cancel = ",                  tostring(job._cancel),
        ", once = ",                    tostring(job._once),
        ", offset.hour = ",             tostring(offset.hour),
        ", offset.minute = ",           tostring(offset.minute),
        ", offset.second = ",           tostring(offset.second),
        ", offset.msec = ",             tostring(offset.msec),
        ", next.hour = ",               tostring(next_pointer
                                                [constants.HOUR_WHEEL_ID]),
        ", next.minute = ",             tostring(next_pointer
                                                [constants.MINUTE_WHEEL_ID]),
        ", next.second = ",             tostring(next_pointer
                                                [constants.SECOND_WHEEL_ID]),
        ", next.msec = ",               tostring(next_pointer
                                                [constants.MSEC_WHEEL_ID]),
        ", elapsed_time.max = ",        tostring(elapsed_time.max),
        ", elapsed_time.min = ",        tostring(elapsed_time.min),
        ", elapsed_time.avg = ",        tostring(elapsed_time.avg),
        ", elapsed_time.variance = ",   tostring(elapsed_time.variance),
        ", meta.name = ",               tostring(meta.name),
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

    -- job_create_meta + job.new + create + once | every = 4
    -- function `create` in file `lib/resty/timer/init.lua`
    local base_callstack_level = 4

    for i = 1, 3 do
        local info = debug_getinfo(i + base_callstack_level, "nSl")

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
local function job_re_cal_next_pointer(job, wheel_group)
    local offset_hour = job.offset.hour
    local offset_minute = job.offset.minute
    local offset_second = job.offset.second
    local offset_msec = job.offset.msec

    local hour_wheel = wheel_group.hour_wheel
    local minute_wheel = wheel_group.minute_wheel
    local second_wheel = wheel_group.second_wheel
    local msec_wheel = wheel_group.msec_wheel
    local lowest_wheel = wheel_group.lowest_wheel

    local cur_hour_pointer = hour_wheel:get_cur_pointer()
    local cur_minute_pointer = minute_wheel:get_cur_pointer()
    local cur_second_pointer = second_wheel:get_cur_pointer()
    local cur_msec_pointer = msec_wheel:get_cur_pointer()

    local cur_pointers = {
        cur_msec_pointer,
        cur_second_pointer,
        cur_minute_pointer,
        cur_hour_pointer,
    }

    local offsets = {
        offset_msec,
        offset_second,
        offset_minute,
        offset_hour,
    }

    local next_msec_pointer,
          next_second_pointer,
          next_minute_pointer,
          next_hour_pointer =
            lowest_wheel:cal_pointer_cascade(cur_pointers, offsets)


    -- Suppose a job will expire in one minute
    -- and we need to spin the pointer of the `minute_wheel`,
    -- but obviously we should not make the
    -- second and msec pointer pointing to zero,
    -- they should point to the current position.

    if next_hour_pointer ~= 0 then
        next_minute_pointer = next_minute_pointer == 0
            and cur_minute_pointer or next_minute_pointer

        next_second_pointer = next_second_pointer == 0
            and cur_second_pointer or next_second_pointer

        next_msec_pointer = next_msec_pointer == 0
            and cur_msec_pointer or next_msec_pointer

    elseif next_minute_pointer ~= 0 then
        next_second_pointer = next_second_pointer == 0
            and cur_second_pointer or next_second_pointer

        next_msec_pointer = next_msec_pointer == 0
            and cur_msec_pointer or next_msec_pointer

    elseif next_second_pointer ~= 0 then
        next_msec_pointer = next_msec_pointer == 0
            and cur_msec_pointer or next_msec_pointer

    -- else
    --     nop
    end


    assert(next_hour_pointer ~= 0 or
           next_minute_pointer ~= 0 or
           next_second_pointer ~= 0 or
           next_msec_pointer ~= 0, "unexpected error")

    job.next_pointer[constants.HOUR_WHEEL_ID] = next_hour_pointer
    job.next_pointer[constants.MINUTE_WHEEL_ID] = next_minute_pointer
    job.next_pointer[constants.SECOND_WHEEL_ID] = next_second_pointer
    job.next_pointer[constants.MSEC_WHEEL_ID] = next_msec_pointer
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


function _M:is_enabled()
    return self._enable
end


function _M:is_oneshot()
    return self._once
end


function _M:is_cancelled()
    return self._cancel
end


function _M:is_runnable()
    return self._enable and not self._cancel and not self._running
end


function _M:is_immediate()
    return self._immediate
end


function _M:get_metadata()
    return utils.table_deepcopy(self.meta)
end


function _M:get_next_pointer(wheel_id)
    return self.next_pointer[wheel_id]
end


function _M:re_cal_next_pointer(wheels)
    job_re_cal_next_pointer(self, wheels)
end


function _M.new(wheels, name, callback, delay, once, args)
    local delay_origin = delay
    local offset_hour, offset_minute, offset_second, offset_msec
    local immediate = true

    if delay ~= 0 then
        immediate = false

        delay, offset_msec = modf(delay)
        offset_msec = offset_msec * 1000 + 10
        offset_msec = floor(floor(offset_msec) / 100)

        -- Arithmetically, the maximum of `offset_msec`
        -- should be `9` now,
        -- but due to floating point errors,
        -- there may be some unexpected cases here.
        -- So here we deal with it.
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
        _immediate = immediate,
        name = name,
        callback = callback,
        delay = delay_origin,
        offset = {
            hour = offset_hour,
            minute = offset_minute,
            second = offset_second,
            msec = offset_msec,
        },

        -- map from `wheel_id` to `next_pointer`
        next_pointer = {},

        _once = once,
        args = args,
        stats = {
            elapsed_time = {
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

    if not immediate then
        job_re_cal_next_pointer(self, wheels)
    end

    return setmetatable(self, meta_table)
end


function _M:execute()
    local stats = self.stats
    local elapsed_time = stats.elapsed_time
    stats.runs = stats.runs + 1
    local start = now()

    if not self:is_runnable() then
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

    elapsed_time.max = max(elapsed_time.max, spend)
    elapsed_time.min = min(elapsed_time.min, spend)

    local old_avg = elapsed_time.avg
    elapsed_time.avg = utils.get_avg(spend, finish, old_avg)

    local old_variance = elapsed_time.variance
    elapsed_time.variance = utils.get_variance(spend, finish, old_variance, old_avg)

end


return _M