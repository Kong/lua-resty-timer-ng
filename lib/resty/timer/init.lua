local semaphore = require "ngx.semaphore"

-- TODO: use it to readuce overhead
-- local new_tab = require "table.new"

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

local job_module = require("resty.timer.job")
local utils_module = require("resty.timer.utils")
local wheel_module = require("resty.timer.wheel")
local constants = require("resty.timer.constants")

local _M = {}


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


local function update_closet(self)
    local old_closet = self.closet
    local delay = 0
    local msec_wheel = self.wheels.msec
    local cur_msec_pointer = msec_wheel:get_cur_pointer()
    for i = 1, 9 do
        local pointer, is_move_to_start = msec_wheel:cal_pointer(cur_msec_pointer, i)

        delay = delay + constants.RESOLUTION

        if is_move_to_start then
            break
        end

        local jobs = msec_wheel:get_jobs_by_pointer(pointer)

        if not utils_module.is_empty_table(jobs) then
            break
        end
    end

    -- TODO: to calculate this value, a baseline is needed,
    --  i.e. the time when the super timer was last woken up.
    self.closet = delay

    return delay < old_closet
end


-- do the following things
-- * add all expired jobs from wheels to `wheels.ready_jobs`
-- * move some jobs from higher wheel to lower wheel
local function fetch_all_expired_jobs(self)
    local wheels = self.wheels

    local hour_wheel = wheels.hour
    local minute_wheel = wheels.min
    local second_wheel = wheels.sec
    local msec_wheel = wheels.msec


    local callbacks = hour_wheel:get_jobs()

    if callbacks then
        for name, job in pairs(callbacks) do

            local next = job.next_pointer

            if next.minute ~= 0 then
                minute_wheel:insert(job.next_pointer.minute, job)

            elseif next.second ~= 0 then
                second_wheel:insert(job.next_pointer.second, job)

            elseif next.msec ~= 0 then
                msec_wheel:insert(job.next_pointer.msec, job)

            else
                wheels.ready_jobs[name] = job
            end

            callbacks[name] = nil
        end
    end

    callbacks = minute_wheel:get_jobs()

    if callbacks then
        for name, job in pairs(callbacks) do

            if job:is_runable() then
                local next = job.next_pointer

                if next.second ~= 0 then
                    second_wheel:insert(job.next_pointer.second, job)

                elseif next.msec ~= 0 then
                    msec_wheel:insert(job.next_pointer.msec, job)

                else
                    wheels.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end

    callbacks = second_wheel:get_jobs()

    if callbacks then
        for name, job in pairs(callbacks) do

            if job:is_runable() then
                local next = job.next_pointer

                if next.msec ~= 0 then
                    msec_wheel:insert(job.next_pointer.msec, job)

                else
                    wheels.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end


    callbacks = msec_wheel:get_jobs()

    if callbacks then
        for name, job in pairs(callbacks) do
            if job:is_runable() then
                wheels.ready_jobs[name] = job
            end

            callbacks[name] = nil
        end
    end
end


local function update_all_wheels(self)
    local wheels = self.wheels

    local hour_wheel = wheels.hour
    local minute_wheel = wheels.min
    local second_wheel = wheels.sec
    local msec_wheel = wheels.msec

    fetch_all_expired_jobs(self)

    update_time()
    self.real_time = now()

    while utils_module.float_compare(self.real_time, self.expected_time) == 1 do
        local _, continue = msec_wheel:move_to_next()

        if continue then
            _, continue = second_wheel:move_to_next()

            if continue then
                _, continue = minute_wheel:move_to_next()

                if continue then
                    _, _ = hour_wheel:move_to_next()
                end

            end
        end

        fetch_all_expired_jobs(self)
        self.expected_time =  self.expected_time + constants.RESOLUTION
    end
end


-- insert a job into the wheel group
local function insert_job_to_wheel(self, job)
    local ok, err

    local wheels = self.wheels
    local hour_wheel = wheels.hour
    local minute_wheel = wheels.min
    local second_wheel = wheels.sec
    local msec_wheel = wheels.msec

    if job.next_pointer.hour ~= 0 then
        ok, err = hour_wheel:insert(job.next_pointer.hour, job)

    elseif job.next_pointer.minute ~= 0 then
        ok, err = minute_wheel:insert(job.next_pointer.minute, job)

    elseif job.next_pointer.second ~= 0 then
        ok, err = second_wheel:insert(job.next_pointer.second, job)

    elseif job.next_pointer.msec ~= 0 then
        ok, err = msec_wheel:insert(job.next_pointer.msec, job)

    else
        assert(false, "unexpected error")
    end

    if not ok then
        return false, err
    end

    return true, nil
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

        local is_no_pending_jobs = utils_module.is_empty_table(wheels.pending_jobs)
        local is_no_ready_jobs = utils_module.is_empty_table(wheels.ready_jobs)

        if not is_no_pending_jobs then
            semaphore_worker:post(opt_threads)

        elseif is_no_pending_jobs and not is_no_ready_jobs then
            wheels.pending_jobs = wheels.ready_jobs
            wheels.ready_jobs = {}
            semaphore_worker:post(opt_threads)
        end
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

        while not utils_module.is_empty_table(wheels.pending_jobs) do
            thread.counter.runs = thread.counter.runs + 1

            local job = utils_module.get_a_item_from_table(wheels.pending_jobs)

            wheels.pending_jobs[job.name] = nil

            if job:is_runable() then
                job:execute()

                if job:is_once() then
                    jobs[job.name] = nil

                elseif job:is_runable() then
                    update_all_wheels(self)
                    job:re_cal_next_pointer(wheels)
                    insert_job_to_wheel(self, job)
                    wake_up_super_timer(self)
                end
            end
        end

        if not utils_module.is_empty_table(wheels.ready_jobs) then
            wake_up_mover_timer(self)
        end

        if thread.counter.runs > self.opt.recreate_interval == 0 then
            thread.counter.runs = 0
            -- TODO: check return value
            timer_at(0, worker_timer_callback, self, thread_index)
            break
        end

    end
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
            assert((timer_at(0, worker_timer_callback, self, i)),
                "failed to create native timer")
        end
    end

    sleep(constants.RESOLUTION)

    update_time()
    self.real_time = now()
    self.expected_time = self.real_time - constants.RESOLUTION

    while not exiting() and not self.destory do
        if premature then
            return
        end

        if self.enable then
            update_all_wheels(self)

            if not utils_module.is_empty_table(wheels.ready_jobs) then
                wake_up_mover_timer(self)
            end

            update_closet(self)
            local closet = max(self.closet, constants.RESOLUTION)
            self.closet = huge
            semaphore_super:wait(closet)

        else
            sleep(constants.RESOLUTION)
        end
    end
end


local function create(self ,name, callback, delay, once, args)
    local jobs = self.jobs
    if not name then
        name = tostring(math.random())
    end

    if jobs[name] then
        return false, "already exists timer"
    end

    update_all_wheels(self)

    local job = job_module.new(self.wheels, name, callback, delay, once, args)
    job:enable()
    jobs[name] = job

    if job:is_immediately() then
        self.wheels.ready_jobs[name] = job
        wake_up_mover_timer(self)

        return true, nil
    end

    local ok, err = insert_job_to_wheel(self, job)

    wake_up_super_timer(self)

    return ok, err
end


function _M:configure(options)
    if self.configured then
        return false, "already configured"
    end

    if options then
        assert(type(options) == "table", "expected `options` to be a table")

        if options.recreate_interval then
            assert(type(options.recreate_interval) == "number", "expected `recreate_interval` to be a number")
            assert(options.recreate_interval > 0, "expected `recreate_interval` to be greater than 0")

            local _, tmp = modf(options.recreate_interval)
            assert(tmp == 0, "expected `recreate_interval` to be a integer")
        end

        if options.threads then
            assert(type(options.threads) == "number",  "expected `threads` to be a number")
            assert(options.threads > 0, "expected `threads` to be greater than 0")

            local _, tmp = modf(options.threads)
            assert(tmp == 0, "expected `threads` to be a integer")
        end
    end

    local opt = {
        -- restart a timer after a certain number of this timer runs
        recreate_interval = options and options.recreate_interval or constants.DEFAULT_RECREATE_INTERVAL,

        -- number of timer will be created by OpenResty API
        threads = options and options.threads or constants.DEFAULT_THREADS,

        -- call function `ngx.update_time` every run of timer job
        fouce_update_time = options and options.fouce_update_time or constants.DEFAULT_FOCUS_UPDATE_TIME,
    }

    self.opt = opt

    -- enable/diable entire timing system
    self.enable = false

    self.threads = {}
    self.jobs = {}

    -- the right time
    self.real_time = 0

    -- expected time for this library
    self.expected_time = 0

    -- has the super timer already been created?
    self.super_timer = false

    -- has the mover timer already been created?
    self.mover_timer = false

    self.destory = false

    self.closet = huge

    self.semaphore_super = semaphore.new(0)

    self.semaphore_worker = semaphore.new(0)

    self.semaphore_mover = semaphore.new(0)

    self.wheels = {
        -- will be move to `pending_jobs` by function `mover_timer_callback`
        -- the function `fetch_all_expired_jobs` adds all expired job to this table
        ready_jobs = {},

        -- each job in this table will be run by function `worker_timer_callback`
        pending_jobs = {},

        -- 100ms per slot
        msec = wheel_module.new(constants.MSEC_WHEEL_SLOTS),

        -- 1 second per slot
        sec = wheel_module.new(constants.SECOND_WHEEL_SLOTS),

        -- 1 minute per slot
        min = wheel_module.new(constants.MINUTE_WHEEL_SLOTS),

        -- 1 hour per slot
        hour = wheel_module.new(constants.HOUR_WHEEL_SLOTS),
    }

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
        ok, err = timer_at(0, super_timer_callback, self)
        self.super_timer = true

        if ok then
            ok, err = timer_at(0, mover_timer_callback, self)
        end
    end

    if not self.enable then
        update_time()
        self.expected_time = now()
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

    if delay >= constants.MAX_EXPIRE or (delay ~= 0 and delay < constants.RESOLUTION) or not self.configured then
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

    if interval >= constants.MAX_EXPIRE or interval < constants.RESOLUTION or not self.configured then
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
            return create(self, old_job.name, old_job.callback, old_job.delay.origin, old_job:is_once(), old_job.args)

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