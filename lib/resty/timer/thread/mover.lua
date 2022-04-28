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

local math_abs = math.abs

local setmetatable = setmetatable

local _M = {
    RESTART_THREAD_AFTER_RUNS = 10 ^ 5,
}

local meta_table = {
    __index = _M,
}


local function thread_init(context)
    context.counter = {
        runs = 0
    }
    return loop.ACTION_CONTINUE
end


local function thread_before(context, self)
    local wake_up_semaphore = self.wake_up_semaphore
    local ok, err =
        wake_up_semaphore:wait(constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR,
                "failed to wait semaphore: "
             .. err)
    end

    return loop.ACTION_CONTINUE
end


local function thread_body(context, self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    local is_no_pending_jobs =
        utils.array_isempty(wheels.pending_jobs)

    local is_no_ready_jobs =
        utils.array_isempty(wheels.ready_jobs)

    if not is_no_pending_jobs then
        self.wake_up_worker_thread()
        return loop.ACTION_CONTINUE
    end

    if not is_no_ready_jobs then
        -- just swap two lists
        -- `wheels.ready_jobs = {}` will bring work to GC
        local temp = wheels.pending_jobs
        wheels.pending_jobs = wheels.ready_jobs
        wheels.ready_jobs = temp
        self.wake_up_worker_thread()
    end

    return loop.ACTION_CONTINUE
end


local function thread_after(context)
    local counter = context.counter
    local runs = counter.runs + 1

    counter.runs = runs

    if runs > _M.RESTART_THREAD_AFTER_RUNS then
        return loop.ACTION_RESTART
    end

    return loop.ACTION_CONTINUE
end


local function thread_finally(context)
    context.counter.runs = 0
    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_worker_thread_callback(callback)
    self.wake_up_worker_thread = callback
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

    self.thread = loop.new("mover", {
        init = {
            argc = 0,
            argv = {},
            callback = thread_init,
        },

        before = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_before,
        },

        loop_body = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_body,
        },

        after = {
            argc = 0,
            argv = {},
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