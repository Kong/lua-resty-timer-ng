local utils = require("resty.timerng.utils")

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local utils_table_deepcopy = utils.table_deepcopy
local utils_convert_second_to_step = utils.convert_second_to_step
local utils_get_avg = utils.get_avg
local utils_get_variance =  utils.get_variance

local table_unpack = table.unpack
local table_concat = table.concat
local table_insert = table.insert

local math_max = math.max
local math_min = math.min
local math_floor = math.floor

local pcall = pcall

local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_worker_exiting = ngx.worker.exiting

local setmetatable = setmetatable
local tostring = tostring
local pairs = pairs

local string_format = string.format

local NAME_COUNTER = 0

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


function _M:is_running()
    return self._running
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
    return   self:is_enabled()
        and  not self:is_cancelled()
        and  not self:is_running()
end


function _M:is_immediate()
    return self._immediate
end


function _M:get_metadata()
    return utils_table_deepcopy(self.meta)
end


function _M:get_stats()
    return utils_table_deepcopy(self.stats)
end


function _M:get_next_pointer(wheel_id)
    return self.next_pointers[wheel_id]
end


function _M:re_cal_next_pointer(wheel_group)
    job_re_cal_next_pointer(self, wheel_group)
end


function _M.new(wheel_group,name, callback, delay, once,
                debug, top_frame, fold_callstack, argc, argv)
    local self = {
        _enable = true,
        _cancel = false,
        _running = false,
        _immediate = delay == 0,
        name = name,
        callback = callback,
        delay = delay,
        debug = debug,
        steps = utils_convert_second_to_step(delay, wheel_group.resolution),

        -- a table
        -- map from `wheel_id` to `next_pointer`
        -- will be assigned by `self:re_cal_next_pointer()`
        next_pointers = nil,

        _once = once,
        argc = argc,
        argv = argv,
        stats = {
            elapsed_time = {
                avg = 0,
                max = -1,
                min = 9999999,
                variance = 0,
            },

            runs = 0,
            finish = 0,
            last_err_msg = "",
        },
    }

    if debug then
        self.meta = {
            name = top_frame,
            callstack = fold_callstack,
        }
    end

    if self.name == nil then
        local meta_name = self.meta and self.meta.name or "non-debug-mode"
        self.name = string_format("unix_timestamp=%f;counter=%d:meta=%s",
                                  math_floor(ngx_now() * 1000),
                                  NAME_COUNTER,
                                  meta_name)

        NAME_COUNTER = NAME_COUNTER + 1
    end

    if not self.immediate then
        job_re_cal_next_pointer(self, wheel_group)
    end

    return setmetatable(self, meta_table)
end


function _M:execute()
    if not self:is_runnable() then
        return
    end

    local stats = self.stats
    local elapsed_time = stats.elapsed_time
    stats.runs = stats.runs + 1
    local start = ngx_now()

    self._running = true

    local ok, err = pcall(self.callback, ngx_worker_exiting(),
                          table_unpack(self.argv, 1, self.argc))

    local finish = stats.finish

    if ok then
        finish = finish + 1

    else
        stats.last_err_msg = err
        ngx_log(ngx_ERR,
                "[timer-ng] failed to run timer ",
                self.name,
                ": ",
                err)
    end

    self._running = false
    stats.finish = finish

    if self.debug then
        ngx_update_time()
        local spend = ngx_now() - start

        elapsed_time.max = math_max(elapsed_time.max, spend)
        elapsed_time.min = math_min(elapsed_time.min, spend)

        local old_avg = elapsed_time.avg
        elapsed_time.avg = utils_get_avg(spend, finish, old_avg)

        local old_variance = elapsed_time.variance
        elapsed_time.variance =
            utils_get_variance(spend, finish, old_variance, old_avg)
    end

end


return _M