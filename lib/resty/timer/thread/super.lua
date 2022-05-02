local semaphore = require("ngx.semaphore")
local loop = require("resty.timer.thread.loop")
local utils = require("resty.timer.utils")
local constants = require("resty.timer.constants")

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_STDERR = ngx.STDERR
local ngx_EMERG = ngx.EMERG
local ngx_ALERT = ngx.ALERT
local ngx_CRIT = ngx.CRIT
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
-- luacheck: pop

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local utils_array_isempty = utils.array_isempty

local ngx_now = ngx.now
local ngx_sleep = ngx.sleep
local ngx_update_time = ngx.update_time

local math_abs = math.abs
local math_max = math.max
local math_min = math.min

local setmetatable = setmetatable

local _M = {
    RESTART_THREAD_AFTER_RUNS = 10 ^ 5,
}

local meta_table = {
    __index = _M,
}


local function thread_init(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels
    local opt_resolution = timer_sys.opt.resolution

    ngx_sleep(opt_resolution)

    ngx_update_time()
    wheels.real_time = ngx_now()
    wheels.expected_time = wheels.real_time - opt_resolution

    context.counter = {
        runs = 0,
    }

    return loop.ACTION_CONTINUE
end


local function thread_body(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    if timer_sys.enable then
        -- update the status of the wheel group
        wheels:sync_time()

        if not utils_array_isempty(wheels.ready_jobs) then
            self.wake_up_mover_thread()
        end
    end

    return loop.ACTION_CONTINUE
end


local function thread_after(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels
    local counter = context.counter
    local runs = counter.runs + 1

    counter.runs = runs

    local delay, _ = wheels:update_earliest_expiry_time()

    delay = math_max(delay, timer_sys.opt.resolution)
    delay = math_min(delay,
                     constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    local ok, err = self.wake_up_semaphore:wait(delay)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR,
                "[timer] failed to wait semaphore: "
             .. err)
    end

    if runs > _M.RESTART_THREAD_AFTER_RUNS then
        return loop.ACTION_RESTART
    end

    return loop.ACTION_CONTINUE
end


local function thread_finally(context)
    context.counter.runs = 0
    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_mover_thread_callback(callback)
    self.wake_up_mover_thread = callback
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