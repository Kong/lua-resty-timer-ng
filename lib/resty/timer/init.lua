local pairs = pairs

local semaphore = require("ngx.semaphore")
local job_module = require("resty.timer.job")
local utils = require("resty.timer.utils")
local wheel_group = require("resty.timer.wheel.group")
local constants = require("resty.timer.constants")

-- TODO: use it to readuce overhead
-- local new_tab = require "table.new"

local ngx = ngx

local max = math.max
local modf = math.modf
local huge = math.huge
local abs = math.abs

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local timer_at = ngx.timer.at
local timer_every = ngx.timer.every
local sleep = ngx.sleep
local exiting = ngx.worker.exiting
local now = ngx.now
local update_time = ngx.update_time

local assert = utils.assert

local _M = {}


local function native_timer_at(delay, callback, ...)
    local ok, err = timer_at(delay, callback, ...)
    assert(ok,
        constants.MSG_FATAL_FAILED_CREATE_NATIVE_TIMER
        -- `err` maybe `nil`
        .. tostring(err))
end


-- post some resources until `self.semaphore_super:count() == 1`
local function wake_up_super_timer(self)
    local semaphore_super = self.semaphore_super

    local count = semaphore_super:count()

    if count <= 0 then
        semaphore_super:post(abs(count) + 1)
    end
end


-- post some resources until `self.semaphore_mover:count() == 1`
local function wake_up_mover_timer(self)
    local semaphore_mover = self.semaphore_mover

    local count = semaphore_mover:count()

    if count <= 0 then
        semaphore_mover:post(abs(count) + 1)
    end
end


-- move all jobs from `self.wheels.ready_jobs` to `self.wheels.pending_jobs`
-- wake up the worker timer
local function mover_timer_callback(premature, self)
    local semaphore_worker = self.semaphore_worker
    local semaphore_mover = self.semaphore_mover
    local opt_threads = self.opt.threads
    local wheels = self.wheels

    if premature then
        return
    end

    while not exiting() and not self.destory do
        -- TODO: check the return value
        semaphore_mover:wait(1)

        local is_no_pending_jobs =
            utils.is_empty_table(wheels.pending_jobs)

        local is_no_ready_jobs =
            utils.is_empty_table(wheels.ready_jobs)

        if not is_no_pending_jobs then
            semaphore_worker:post(opt_threads)
            goto continue
        end

        if not is_no_ready_jobs then
            wheels.pending_jobs = wheels.ready_jobs
            wheels.ready_jobs = {}
            semaphore_worker:post(opt_threads)
        end

        ::continue::
    end
end


-- exec all expired jobs
-- re-insert the recurrent job
-- delete once job from `self.jobs`
-- wake up the mover timer
local function worker_timer_callback(premature, self, thread_index)
    local semaphore_worker = self.semaphore_worker
    local thread = self.threads[thread_index]
    local wheels = self.wheels
    local jobs = self.jobs

    while not exiting() and not self.destory do
        if premature then
            return
        end

        -- TODO: check the return value
        semaphore_worker:wait(1)

        while not utils.is_empty_table(wheels.pending_jobs) do
            thread.counter.runs = thread.counter.runs + 1

            local job = utils.get_a_item_from_table(wheels.pending_jobs)

            wheels.pending_jobs[job.name] = nil

            if job:is_runable() then
                job:execute()

                if job:is_once() then
                    jobs[job.name] = nil
                    goto continue
                end

                if job:is_runable() then
                    wheels:sync_time()
                    job:re_cal_next_pointer(wheels)
                    wheels:insert_job(job)
                    wake_up_super_timer(self)
                end
            end

            ::continue::
        end

        if not utils.is_empty_table(wheels.ready_jobs) then
            wake_up_mover_timer(self)
        end

        if thread.counter.runs > self.opt.restart_thread_after_runs then
            thread.counter.runs = 0

            -- Since the native timer only releases resources when it is destroyed,
            -- including resources created by `job:execute()`
            -- it needs to be destroyed and recreated periodically.
            native_timer_at(0, worker_timer_callback, self, thread_index)
            break
        end

    end -- the top while
end


-- do the following things
-- * create all worker timer
-- * wake up mover timer
-- * update the status of all wheels
-- * calculate wait time for `semaphore_super`
local function super_timer_callback(premature, self)
    local semaphore_super = self.semaphore_super
    local threads = self.threads
    local opt_threads = self.opt.threads
    local wheels = self.wheels

    self.super_timer = true

    for i = 1, opt_threads do
        if not threads[i].alive then
            native_timer_at(0, worker_timer_callback, self, i)
        end
    end

    sleep(constants.RESOLUTION)

    update_time()
    wheels.real_time = now()
    wheels.expected_time = wheels.real_time - constants.RESOLUTION

    while not exiting() and not self.destory do
        if premature then
            return
        end

        if self.enable then
            wheels:sync_time()

            if not utils.is_empty_table(wheels.ready_jobs) then
                wake_up_mover_timer(self)
            end

            wheels:update_closest()
            local closest = max(wheels.closest, constants.RESOLUTION)
            wheels.closest = huge
            semaphore_super:wait(closest)

        else
            sleep(constants.RESOLUTION)
        end
    end
end


local function create(self ,name, callback, delay, once, args)
    local wheels = self.wheels
    local jobs = self.jobs
    if not name then
        name = tostring(math.random())
    end

    if jobs[name] then
        return false, "already exists timer"
    end

    wheels:sync_time()

    local job = job_module.new(wheels, name, callback, delay, once, args)
    job:enable()
    jobs[name] = job

    if job:is_immediately() then
        self.wheels.ready_jobs[name] = job
        wake_up_mover_timer(self)

        return true, nil
    end

    local ok, err = wheels:insert_job(job)

    wake_up_super_timer(self)

    return ok, err
end


function _M:configure(options)
    if self.configured then
        return false, "already configured"
    end

    if options then
        assert(type(options) == "table", "expected `options` to be a table")

        if options.restart_thread_after_runs then
            assert(type(options.restart_thread_after_runs) == "number",
                "expected `restart_thread_after_runs` to be a number")

            assert(options.restart_thread_after_runs > 0,
                "expected `restart_thread_after_runs` to be greater than 0")

            local _, tmp = modf(options.restart_thread_after_runs)

            assert(tmp == 0,
                "expected `restart_thread_after_runs` to be a integer")
        end

        if options.threads then
            assert(type(options.threads) == "number",
                "expected `threads` to be a number")

            assert(options.threads > 0,
            "expected `threads` to be greater than 0")

            local _, tmp = modf(options.threads)
            assert(tmp == 0, "expected `threads` to be a integer")
        end
    end

    local opt = {
        -- restart the thread after every n jobs have been run
        restart_thread_after_runs = options
            and options.restart_thread_after_runsor
            or constants.DEFAULT_RESTART_THREAD_AFTER_RUNS,

        -- number of timer will be created by OpenResty API
        threads = options
            and options.threads
            or constants.DEFAULT_THREADS,

        -- call function `ngx.update_time` every run of timer job
        fouce_update_time = options
            and options.fouce_update_time
            or constants.DEFAULT_FOCUS_UPDATE_TIME,
    }

    self.opt = opt

    -- enable/diable entire timing system
    self.enable = false

    self.threads = {}
    self.jobs = {}

    -- has the super timer already been created?
    self.super_timer = false

    -- has the mover timer already been created?
    self.mover_timer = false

    self.destory = false

    self.semaphore_super = semaphore.new(0)

    self.semaphore_worker = semaphore.new(0)

    self.semaphore_mover = semaphore.new(0)

    self.wheels = wheel_group.new()

    for i = 1, self.opt.threads do
        self.threads[i] = {
            index = i,
            alive = false,
            counter = {
                -- number of runs
                runs = 0,
            },
        }
    end

    self.configured = true
    return true, nil
end


function _M:start()
    local ok, err = true, nil

    if not self.super_timer then
        native_timer_at(0, super_timer_callback, self)
        native_timer_at(0, mover_timer_callback, self)
        self.super_timer = true
    end

    if not self.enable then
        update_time()
        self.wheels.expected_time = now()
    end

    self.enable = true

    return ok, err
end


function _M:stop()
    self.enable = false
end


function _M:unconfigure()
    self.destory = true
    self.configured = false
end



function _M:once(name, callback, delay, ...)
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(delay) == "number", "expected `delay to be a number")
    assert(delay >= 0, "expected `delay` to be greater than or equal to 0")

    if delay >= constants.MAX_EXPIRE
        or (delay ~= 0 and delay < constants.RESOLUTION)
        or not self.configured then

        local ok, err = timer_at(delay, callback, ...)
        return ok ~= nil, err
    end

    local ok, err = create(self, name, callback, delay, true, { ... })

    return ok, err
end


function _M:every(name, callback, interval, ...)
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(interval) == "number", "expected `interval to be a number")
    assert(interval > 0, "expected `interval` to be greater than or equal to 0")

    if interval >= constants.MAX_EXPIRE
        or interval < constants.RESOLUTION
        or not self.configured then

        local ok, err = timer_every(interval, callback, ...)
        return ok ~= nil, err
    end

    local ok, err = create(self, name, callback, interval, false, { ... })

    return ok, err
end


function _M:run(name)
    assert(type(name) == "string", "expected `name` to be a string")

    local jobs = self.jobs
    local old_job = jobs[name]
    jobs[name] = nil

    if old_job then

        if not old_job:is_runable() then
            return create(self, old_job.name, old_job.callback,
                old_job.delay, old_job:is_once(), old_job.args)

        else
            return false, "running"
        end

    else
        return false, "timer not found"
    end
end


function _M:pause(name)
    assert(type(name) == "string", "expected `name` to be a string")

    local jobs = self.jobs
    local job = jobs[name]

    if job then

        if job:is_enable() then
            job:pause()

        else
            return false, "already paused"
        end


    else
        return false, "timer not found"
    end

    return true, nil
end


function _M:cancel(name)
    assert(type(name) == "string", "expected `name` to be a string")

    local jobs = self.jobs
    local job = jobs[name]

    if not job then
        return false, "timer not found"
    end

    job:cancel()
    jobs[name] = nil

    return true, nil
end


function _M:stats()
    local pending_jobs = self.wheels.pending_jobs

    local sys = {
        running = 0,
        pending = 0,
        waiting = 0,
    }

    local jobs = {}

    for name, job in pairs(self.jobs) do
        if job.running then
            sys.running = sys.running + 1

        elseif not pending_jobs[name] then
            sys.pending = sys.pending + 1

        else
            sys.waiting = sys.waiting + 1
        end

        local stats = job.stats
        jobs[name] = {
            name = name,
            meta = job.meta,
            runtime = job.runtime,
            runs = stats.runs,
            faults = stats.faults,
            last_err_msg = stats.last_err_msg,
        }
    end


    return {
        sys = sys,
        timers = jobs,
    }
end


return _M