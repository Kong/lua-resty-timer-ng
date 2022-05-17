local semaphore = require("ngx.semaphore")
local loop = require("resty.timer.thread.loop")
local constants = require("resty.timer.constants")

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local ngx_worker_exiting = ngx.worker.exiting

local string_format = string.format

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function thread_init(context)
    context.counter = {
        runs = 0,
    }
    return loop.ACTION_CONTINUE
end


local function thread_before(context, self)
    local wake_up_semaphore = self.wake_up_semaphore
    local ok, err =
        wake_up_semaphore:wait(constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR,
                "[timer] failed to wait semaphore: "
             .. err)
    end

    return loop.ACTION_CONTINUE
end


local function thread_body(context, self)
    local timer_sys = self.timer_sys
    local counter = timer_sys.counter
    local wheels = timer_sys.wheels

    while not wheels.pending_jobs:is_empty() and
          not ngx_worker_exiting()
    do
        local job = wheels.pending_jobs:pop_back()

        if not job:is_runnable() then
            goto continue
        end

        counter.running = counter.running + 1
        job:execute()
        counter.running = counter.running - 1
        counter.runs = counter.runs + 1

        if job:is_oneshot() then
            timer_sys:cancel(job.name)
            goto continue
        end

        if job:is_runnable() then
            wheels:sync_time()
            job:re_cal_next_pointer(wheels)
            wheels:insert_job(job)

            local _, need_wake_up = wheels:update_earliest_expiry_time()

            if need_wake_up then
                self.wake_up_super_thread()
            end
        end

        ::continue::
    end

    if not wheels.ready_jobs:is_empty() then
        self.wake_up_super_thread()
    end

    return loop.ACTION_CONTINUE
end


local function thread_after(context, restart_thread_after_runs)
    local counter = context.counter
    local runs = counter.runs + 1

    counter.runs = runs

    if runs > restart_thread_after_runs then
        return loop.ACTION_RESTART
    end

    return loop.ACTION_CONTINUE
end


local function thread_finally(context)
    context.counter.runs = 0
    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_super_thread_callback(callback)
    self.wake_up_super_thread = callback
end


function _M:kill()
    local threads = self.threads
    for i = 1, #threads do
        threads[i]:kill()
    end
end


function _M:wake_up()
    local wake_up_semaphore = self.wake_up_semaphore
    wake_up_semaphore:post(#self.threads)
end


function _M:spawn()
    local ok, err
    local threads = self.threads
    for i = 1, #threads do
        ok, err = threads[i]:spawn()

        if not ok then
            return false, err
        end
    end

    return true, nil
end


function _M.new(timer_sys, threads)
    local self = {
        timer_sys = timer_sys,
        wake_up_semaphore = semaphore.new(0),
        threads = {},
    }

    for i = 1, threads do
        local name = string_format("worker#%d", i)
        self.threads[i] = loop.new(name, {
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
                argc = 1,
                argv = {
                    timer_sys.opt.restart_thread_after_runs,
                },
                callback = thread_after,
            },

            finally = {
                argc = 0,
                argv = {},
                callback = thread_finally,
            },
        })
    end

    return setmetatable(self, meta_table)
end


return _M