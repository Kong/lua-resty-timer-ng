local semaphore = require("ngx.semaphore")
local loop = require("resty.timer.thread.loop")
local constants = require("resty.timer.constants")

local ngx_log = ngx.log
local ngx_NOTICE = ngx.NOTICE
local ngx_ERR = ngx.ERR

local math_floor = math.floor

local ngx_now = ngx.now
local ngx_worker_exiting = ngx.worker.exiting

local string_format = string.format

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function report_alive(self, thread)
    assert(self.spawned_threads[thread.name] ~= nil)

    self.alive_threads[thread.name] = thread
    self.alive_threads_count = self.alive_threads_count + 1

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] thread %s is alive", thread.name)
    )

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] spawned worker threads: %d",
                      self.spawned_threads_count)
    )

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] alive worker threads: %d",
                      self.alive_threads_count)
    )
end


local function report_exit(self, thread)
    assert(self.spawned_threads[thread.name] ~= nil)
    assert(self.alive_threads[thread.name] ~= nil)

    self.spawned_threads[thread.name] = nil
    self.alive_threads[thread.name] = nil

    self.spawned_threads_count = self.spawned_threads_count - 1
    self.alive_threads_count = self.alive_threads_count - 1

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] thread %s exits", thread.name)
    )

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] spawned worker threads: %d",
                      self.spawned_threads_count)
    )

    ngx_log(
        ngx_NOTICE,
        string_format("[timer] alive worker threads: %d",
                      self.alive_threads_count)
    )
end


local function thread_init(context, report_alive_callback, self)
    report_alive_callback(self, context.self)

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
        local job = wheels.pending_jobs:pop_left()

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

    self.wake_up_super_thread()

    return loop.ACTION_CONTINUE
end


local function thread_after(context, restart_thread_after_runs)
    local counter = context.counter
    local runs = counter.runs + 1

    counter.runs = runs

    if runs > restart_thread_after_runs then
        return loop.ACTION_EXIT
    end

    return loop.ACTION_CONTINUE
end


local function thread_finally(context, report_exit_callback, self)
    context.counter.runs = 0

    if ngx_worker_exiting() then
        local jobs = self.timer_sys.jobs
        local job_name, job = next(jobs)

        while job_name do
            jobs[job_name] = nil
            job:execute()
            job_name, job = next(jobs)
        end
    end

    report_exit_callback(self, context.self)
    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_super_thread_callback(callback)
    self.wake_up_super_thread = callback
end


function _M:kill()
    local spawned_threads = self.spawned_threads
    for _, thread in pairs(spawned_threads) do
        thread:kill()
    end
end


function _M:wake_up()
    local wake_up_semaphore = self.wake_up_semaphore
    wake_up_semaphore:post(self.alive_threads_count)
end


function _M:spawn()
    local ok, err

    while self.spawned_threads_count < self.max_threads do
        local name = string_format(
            "worker#%d#%d",
            math_floor(ngx_now() * 1000),
            self.name_counter)

        self.name_counter = self.name_counter + 1

        self.spawned_threads[name] = loop.new(name, {
            init = self.init,
            before = self.before,
            loop_body = self.loop_body,
            after = self.after,
            finally = self.finally,
        })

        ok, err = self.spawned_threads[name]:spawn()

        if not ok then
            return false, err
        end

        self.spawned_threads_count = self.spawned_threads_count + 1
    end

    return true, nil
end


function _M.new(timer_sys, threads)
    local self = {
        name_counter = 0,
        timer_sys = timer_sys,
        wake_up_semaphore = semaphore.new(0),
        max_threads = threads,

        spawned_threads_count = 0,
        spawned_threads = {},

        alive_threads_count = 0,
        alive_threads = {},
    }

    self.init = {
        argc = 2,
        argv = {
            report_alive,
            self,
        },
        callback = thread_init,
    }

    self.before = {
        argc = 1,
        argv = {
            self,
        },
        callback = thread_before,
    }

    self.loop_body = {
        argc = 1,
        argv = {
            self,
        },
        callback = thread_body,
    }

    self.after = {
        argc = 1,
        argv = {
            self.timer_sys.opt.restart_thread_after_runs,
        },
        callback = thread_after,
    }

    self.finally = {
        argc = 2,
        argv = {
            report_exit,
            self,
        },
        callback = thread_finally,
    }

    return setmetatable(self, meta_table)
end


return _M