local semaphore = require("ngx.semaphore")
local loop = require("resty.timerng.thread.loop")

local ngx_log = ngx.log
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR

local ngx_now = ngx.now
local ngx_sleep = ngx.sleep
local ngx_update_time = ngx.update_time

local math_abs = math.abs
local math_max = math.max
local math_min = math.min

local CONSTANTS_SCALING_RECORD_INTERVAL =
    require("resty.timerng.constants").SCALING_RECORD_INTERVAL
local CONSTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN =
    require("resty.timerng.constants").TOLERANCE_OF_GRACEFUL_SHUTDOWN

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function scaling_init(context)
    context.scaling_info = {
        last_record_time = 0,
        loads = 0,
        load_sum = 0,
    }
end


local function scaling_record(self, context)
    local scaling_info = context.scaling_info

    local now = ngx_now()
    local delta = now - scaling_info.last_record_time

    if delta < CONSTANTS_SCALING_RECORD_INTERVAL then
        return
    end

    scaling_info.last_record_time = now

    local stats_sys = self.timer_sys:stats(false).sys
    local runable_jobs = stats_sys.running + stats_sys.pending
    local alive_threads = self.worker_thread:get_alive_thread_count()
    local load = runable_jobs / alive_threads

    scaling_info.loads = scaling_info.loads + 1
    scaling_info.load_sum = scaling_info.load_sum + load

    ngx_log(ngx_INFO, "alive threads: ", alive_threads)
    ngx_log(ngx_INFO, "runable jobs: ", runable_jobs)
    ngx_log(ngx_INFO, "load: ", load)
end


local function scaling_execute(self, context)
    local scaling_info = context.scaling_info
    local threshold = self.timer_sys.opt.auto_scaling_load_threshold
    local interval = self.timer_sys.opt.auto_scaling_interval

    if scaling_info.loads < interval then
        return
    end

    local load_avg = scaling_info.load_sum / scaling_info.loads

    scaling_info.loads = 0
    scaling_info.load_sum = 0

    if load_avg > threshold then
        local ok, delta_thread_count_or_err =
            self.worker_thread:stretch(0.33)

        if not ok then
            return false, delta_thread_count_or_err
        end

        if delta_thread_count_or_err <= 0 then
            ngx.log(ngx_WARN, "[timer-ng] overload: ", load_avg)
        end

        return true, nil
    end

    if load_avg < 0.6 then
        local ok, err = self.worker_thread:stretch(-0.10)
        return ok, err
    end

    return true, nil
end


local function thread_init(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels
    local opt_resolution = timer_sys.opt.resolution

    ngx_sleep(opt_resolution)

    ngx_update_time()
    wheels.real_time = ngx_now()
    wheels.expected_time = wheels.real_time - opt_resolution

    scaling_init(context)

    return loop.ACTION_CONTINUE
end


local function thread_body(_, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    if timer_sys.enable then
        -- update the status of the wheel group
        wheels:sync_time()

        if not wheels.pending_jobs:is_empty() then
            self.worker_thread:wake_up()
        end
    end

    return loop.ACTION_CONTINUE
end


local function thread_after(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    scaling_record(self, context)
    scaling_execute(self, context)

    self.worker_thread:spawn()

    local delay, _ = wheels:update_earliest_expiry_time()

    delay = math_max(delay, timer_sys.opt.resolution)
    delay = math_min(delay,
                     CONSTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    local ok, err = self.wake_up_semaphore:wait(delay)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR, "[timer-ng] failed to wait semaphore: ", err)
    end

    return loop.ACTION_CONTINUE
end


local function thread_finally(_)
    return loop.ACTION_CONTINUE
end


function _M:set_worker_thread_ref(worker_thread)
    self.worker_thread = worker_thread
end


function _M:kill()
    self.thread:kill()
end


function _M:wake_up()
    local wake_up_semaphore = self.wake_up_semaphore
    local count = wake_up_semaphore:count()

    if count <= 0 then
        wake_up_semaphore:post(math_abs(count) + 1)
    end
end


function _M:spawn()
    return self.thread:spawn()
end


function _M.new(timer_sys)
    local self = {
        timer_sys = timer_sys,
        wake_up_semaphore = semaphore.new(0),
        worker_thread = nil,
    }

    self.thread = loop.new("super", {
        init = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_init,
        },

        loop_body = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_body,
        },

        after = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_after,
        },

        finally = {
            argc = 0,
            argv = {},
            callback = thread_finally,
        }
    })

    return setmetatable(self, meta_table)
end


return _M