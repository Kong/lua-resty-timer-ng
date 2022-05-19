local semaphore = require("ngx.semaphore")
local loop = require("resty.timer.thread.loop")
local constants = require("resty.timer.constants")

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local ngx_now = ngx.now
local ngx_sleep = ngx.sleep
local ngx_update_time = ngx.update_time

local math_abs = math.abs
local math_max = math.max
local math_min = math.min

local setmetatable = setmetatable

local _M = {}

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

    return loop.ACTION_CONTINUE
end


local function thread_body(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    if timer_sys.enable then
        -- update the status of the wheel group
        wheels:sync_time()

        if not wheels.pending_jobs:is_empty() then
            self.wake_up_worker_thread()

        elseif not wheels.ready_jobs:is_empty() then
            -- just swap two lists
            -- `wheels.ready_jobs = {}` will bring work to GC
            local temp = wheels.pending_jobs
            wheels.pending_jobs = wheels.ready_jobs
            wheels.ready_jobs = temp
            self.wake_up_worker_thread()
        end
    end

    return loop.ACTION_CONTINUE
end


local function thread_after(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    self.spawn_worker_thread()

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

    return loop.ACTION_CONTINUE
end


local function thread_finally(context)
    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_worker_thread_callback(callback)
    self.wake_up_worker_thread = callback
end


function _M:set_spawn_worker_thread_callback(callback)
    self.spawn_worker_thread = callback
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