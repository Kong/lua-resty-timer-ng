local semaphore = require("ngx.semaphore")
local constants = require("resty.timerng.constants")
local loop = require("resty.timerng.thread.loop")

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local ngx_now = ngx.now
local ngx_sleep = ngx.sleep
local ngx_update_time = ngx.update_time
local ngx_worker_exiting = ngx.worker.exiting

local math_abs = math.abs
local math_max = math.max
local math_min = math.min

local CONSTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN =
    constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function init_phase_handler(context, self)
    local timer_sys = self.timer_sys
    local wheel_group = timer_sys.thread_group.wheel_group
    local opt_resolution = timer_sys.opt.resolution

    ngx_sleep(opt_resolution)

    ngx_update_time()
    wheel_group.real_time = ngx_now()
    wheel_group.expected_time = wheel_group.real_time - opt_resolution

    return loop.ACTION_CONTINUE
end


local function loop_body_phase_handler(_, self)
    local timer_sys = self.timer_sys
    local wheel_group = timer_sys.thread_group.wheel_group

    if timer_sys.enable then
        -- update the status of the wheel group
        wheel_group:sync_time()
    end

    return loop.ACTION_CONTINUE
end


local function after_phase_handler(context, self)
    local timer_sys = self.timer_sys
    local wheel_group = timer_sys.thread_group.wheel_group

    local delay, _ = wheel_group:update_earliest_expiry_time()

    delay = math_max(delay, timer_sys.opt.resolution)
    delay = math_min(delay,
                     CONSTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    local ok, err = self.wake_up_semaphore:wait(delay)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR, "[timer-ng] failed to wait semaphore: ", err)
    end

    return loop.ACTION_CONTINUE
end


local function finally_phase_handler(context, self)
    if not ngx_worker_exiting() then
        return loop.ACTION_CONTINUE
    end

    local timer_sys = self.timer_sys
    local jobs = timer_sys.jobs

    for _, job in pairs(jobs) do
        job:execute()
    end

    return loop.ACTION_CONTINUE
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
    }

    self.thread = loop.new("super", {
        init = {
            argc = 1,
            argv = {
                self,
            },
            callback = init_phase_handler,
        },

        loop_body = {
            argc = 1,
            argv = {
                self,
            },
            callback = loop_body_phase_handler,
        },

        after = {
            argc = 1,
            argv = {
                self,
            },
            callback = after_phase_handler,
        },

        finally = {
            argc = 1,
            argv = {
                self,
            },
            callback = finally_phase_handler,
        }
    })

    return setmetatable(self, meta_table)
end


return _M