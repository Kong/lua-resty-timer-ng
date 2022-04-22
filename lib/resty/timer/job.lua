local utils = require("resty.timer.utils")

local table_unpack = table.unpack
local table_concat = table.concat
local table_insert = table.insert

local debug_getinfo = debug.getinfo

local math_max = math.max
local math_min = math.min
local math_huge = math.huge

local pcall = pcall

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local ngx_now = ngx.now

local setmetatable = setmetatable
local tostring = tostring
local pairs = pairs

local string_format = string.format

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local _M = {}


local function job_tostring(job)
    local stats = job.stats
    local elapsed_time = stats.elapsed_time
    local meta = job.meta

    local tbl = {
        "name = ",                      tostring(job.name),
        ", enable = ",                  tostring(job._enable),
        ", cancel = ",                  tostring(job._cancel),
        ", once = ",                    tostring(job._once),
        ", steps = ",                   tostring(job.steps),
        ", meta.name = ",               tostring(meta.name),
    }

    for wheel_id, pointer in pairs(job.next_pointers) do
        local str = string_format(", next_pointer.%s = %s",
                                  tostring(wheel_id),
                                  tostring(pointer))
        table_insert(tbl, str)
    end

    for k, v in pairs(elapsed_time) do
        local str = string_format(", elapsed_time.%s = %s",
                                  tostring(k),
                                  tostring(v))
        table_insert(tbl, str)
    end

    return table_concat(tbl)
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
    local lowest_wheel = wheel_group.lowest_wheel

    job.next_pointers = lowest_wheel:cal_pointer_cascade(job.steps)
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
    return self.next_pointers[wheel_id]
end


function _M:re_cal_next_pointer(wheels)
    job_re_cal_next_pointer(self, wheels)
end


function _M.new(wheels, name, callback, delay, once, argc, argv)
    local delay_origin = delay
    local immediate = false

    if delay == 0 then
        immediate = true
    end

    local self = {
        _enable = true,
        _cancel = false,
        _running = false,
        _immediate = immediate,
        name = name,
        callback = callback,
        delay = delay_origin,
        steps = utils.convert_second_to_step(delay, wheels.resolution),

        -- map from `wheel_id` to `next_pointer`
        next_pointers = {},

        _once = once,
        argc = argc,
        argv = argv,
        stats = {
            elapsed_time = {
                avg = 0,
                max = -1,
                min = math_huge,
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
    local start = ngx_now()

    if not self:is_runnable() then
        return
    end

    self._running = true

    local ok, err = pcall(self.callback, false,
                          table_unpack(self.argv, 1, self.argc))

    local finish = stats.finish

    if ok then
        finish = finish + 1

    else
        stats.last_err_msg = err
    end

    self._running = false
    stats.finish = finish

    local spend = ngx_now() - start

    elapsed_time.max = math_max(elapsed_time.max, spend)
    elapsed_time.min = math_min(elapsed_time.min, spend)

    local old_avg = elapsed_time.avg
    elapsed_time.avg = utils.get_avg(spend, finish, old_avg)

    local old_variance = elapsed_time.variance
    elapsed_time.variance =
        utils.get_variance(spend, finish, old_variance, old_avg)

end


return _M