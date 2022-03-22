local semaphore_module = require "ngx.semaphore"
local new_tab = require "table.new"

local unpack = table.unpack
local debug_getinfo = debug.getinfo

local max = math.max
local min = math.min
local floor = math.floor
local modf = math.modf
local ceil = math.ceil
local pow = math.pow
local huge = math.huge
local abs = math.abs

local log = ngx.log
local ERR = ngx.ERR
local timer_at = ngx.timer.at
local timer_every = ngx.timer.every
local sleep = ngx.sleep
local exiting = ngx.worker.exiting
local now = ngx.now
local update_time = ngx.update_time

local FOCUS_UPDATE_TIME = true

local DEFAULT_THREADS = 32
local DEFAULT_MAX_EXPIRE = 24 * 60 * 60
local DEFAULT_RECREATE_INTERVAL = 50
local DEFAULT_FOCUS_UPDATE_TIME = false

local MAX_EXPIRE = 23 * 60 * 60 + 59 * 60

local _M = {}


local function job_tostring(job)
    local str = ""

    local stats = job.stats
    local delay = job.delay
    local next_pointer = job.next_pointer
    local runtime = stats.runtime
    local meta = job.meta

    str = str .. "name = " .. job.name
    str = str .. ", enable = " .. tostring(job.enable)
    str = str .. ", cancel = " .. tostring(job.cancel)
    str = str .. ", delay.hour = " .. tostring(delay.hour)
    str = str .. ", delay.minute = " .. tostring(delay.minute)
    str = str .. ", delay.second = " .. tostring(delay.second)
    str = str .. ", delay.msec = " .. tostring(delay.msec)
    str = str .. ", next.hour = " .. tostring(next_pointer.hour)
    str = str .. ", next.minute = " .. tostring(next_pointer.minute)
    str = str .. ", next.second = " .. tostring(next_pointer.second)
    str = str .. ", next.msec = " .. tostring(next_pointer.msec)
    str = str .. ", runtime.max = " .. runtime.max
    str = str .. ", runtime.min = " .. runtime.min
    str = str .. ", runtime.avg = " .. runtime.avg
    str = str .. ", runtime.variance = " .. runtime.variance
    str = str .. ", meta.name = " .. meta.name

    return str
end


local function is_empty_table(t)
    if not t then
        return true
    end

    for k, v in pairs(t) do
        return false
    end

    return true
end


local function get_a_item_from_table(tbl)
    if not tbl then
        return nil
    end

    for k, v in pairs(tbl) do
        return v
    end

    return nil
end


local function print_queue(self)
    local pending_jobs = self.wheels.pending_jobs
    local ready_jobs = self.wheels.ready_jobs

    update_time()

    local str = "\n======== BEGIN PENDING ========" .. now() .. "\n"

    for _, v in pairs(pending_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END PENDING ========\n"

    str = str .. "======== BEGIN READY ========" .. tostring(self.semaphore_mover:count()) .. "\n"

    for _, v in pairs(ready_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END READY ========"

    log(ERR, str)
end


local function print_wheel(self)
    local _wheel = self.wheels
    local wheel

    update_time()

    local str = "\n======== BEGIN MSEC ========" .. now() .. "\n"
    wheel = _wheel.msec
    str = str .. "pointer = " .. wheel.pointer .. "\n"
    str = str .. "nelt = " .. wheel.nelt .. "\n"
    for i, v in ipairs(wheel.array) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END SECOND =========\n"


    str = "\n======== BEGIN MSEC ========" .. now() .. "\n"
    wheel = _wheel.sec
    str = str .. "pointer = " .. wheel.pointer .. "\n"
    str = str .. "nelt = " .. wheel.nelt .. "\n"
    for i, v in ipairs(wheel.array) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END SECOND ========="


    str = "\n======== BEGIN MINUTE ========" .. now() .. "\n"
    wheel = _wheel.sec
    str = str .. "pointer = " .. wheel.pointer .. "\n"
    str = str .. "nelt = " .. wheel.nelt .. "\n"
    for i, v in ipairs(wheel.array) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END MINUTE ========="


    str = "\n======== BEGIN MINUTE ========" .. now() .. "\n"
    wheel = _wheel.sec
    str = str .. "pointer = " .. wheel.pointer .. "\n"
    str = str .. "nelt = " .. wheel.nelt .. "\n"
    for i, v in ipairs(wheel.array) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END MINUTE ========="

    log(ERR, str)
end


local function round(value, digits)
    local x = 10 * digits
    return floor(value * x + 0.5) / x
end


-- get average
local function get_avg(cur_value, cur_count, old_avg)
    -- recurrence formula
    return old_avg + ((cur_value - old_avg) / cur_count)
end


local function get_variance(cur_value, cur_count, old_variance, old_avg)
    -- recurrence formula
    return (((cur_count - 1) / pow(cur_count, 2)) * pow(cur_value - old_avg, 2)) +
        (((cur_count - 1) / cur_count) * old_variance)
end


local function float_compare(left, right)
    local delta = left - right
    if delta < -0.01 then
        return -1

    elseif delta > 0.01 then
        return 1

    else
        return 0
    end
end


local function wheel_get_cur_pointer(wheel)
    return wheel.pointer
end


local function wheel_cal_pointer(wheel, pointer, offset)
    local nelt = wheel.nelt
    local p = pointer
    local old = p

    p = (p + offset) % (nelt + 1)

    if old + offset > nelt then
        return p + 1, true
    end

    return p, false
end


local function job_pause(job)
    job.enable = false
end


local function job_cancel(job)
    job.enable = false
    job.cancel = true
end


local function job_enable(job)
    job.enable = true
end


local function job_is_enable(job)
    return job.enable
end


local function job_is_once(job)
    return job.once
end


local function job_is_runable(job)
    return job.enable and not job.cancel and not job.running
end


local function job_re_cal_next_pointer(job, wheels)
    local delay_hour = job.delay.hour
    local delay_minute = job.delay.minute
    local delay_second = job.delay.second
    local delay_msec = job.delay.msec

    local hour_wheel = wheels.hour
    local minute_wheel = wheels.min
    local second_wheel = wheels.sec
    local msec_wheel = wheels.msec

    local cur_hour_pointer = wheel_get_cur_pointer(hour_wheel)
    local cur_minute_pointer = wheel_get_cur_pointer(minute_wheel)
    local cur_second_pointer = wheel_get_cur_pointer(second_wheel)
    local cur_msec_pointer = wheel_get_cur_pointer(msec_wheel)

    local next_hour_pointer = 0
    local next_minute_pointer = 0
    local next_second_pointer = 0
    local next_msec_pointer = 0

    local up = false

    if delay_msec then
        next_msec_pointer, up = wheel_cal_pointer(msec_wheel, cur_msec_pointer, delay_msec)
    end

    if delay_second or up then

        if not delay_second then
            delay_second = 0
        end

        if up then
            delay_second = delay_second + 1
        end

        next_second_pointer, up = wheel_cal_pointer(second_wheel, cur_second_pointer, delay_second)

    else
        up = false
    end

    if delay_minute or up then

        if not delay_minute then
            delay_minute = 0
        end

        if up then
            delay_minute = delay_minute + 1
        end

        next_minute_pointer, up = wheel_cal_pointer(minute_wheel, cur_minute_pointer, delay_minute)

    else
        up = false
    end

    if delay_hour or up then

        if not delay_hour then
            delay_hour = 0
        end

        if up then
            delay_hour = delay_hour + 1
        end

        next_hour_pointer, _ = wheel_cal_pointer(minute_wheel, cur_hour_pointer, delay_hour)
    end

    if next_hour_pointer ~= 0 then
        if next_minute_pointer == 0 then
            next_minute_pointer = cur_minute_pointer
        end

        if next_second_pointer == 0 then
            next_second_pointer = cur_second_pointer
        end

        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end

    elseif next_minute_pointer ~= 0 then
        if next_second_pointer == 0 then
            next_second_pointer = cur_second_pointer
        end

        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end

    elseif next_second_pointer ~= 0 then
        if next_msec_pointer == 0 then
            next_msec_pointer = cur_msec_pointer
        end
    end


    assert(next_hour_pointer ~= 0 or
           next_minute_pointer ~= 0 or
           next_second_pointer ~= 0 or
           next_msec_pointer ~= 0, "unexpected error")

    job.next_pointer.hour = next_hour_pointer
    job.next_pointer.minute = next_minute_pointer
    job.next_pointer.second = next_second_pointer
    job.next_pointer.msec = next_msec_pointer
end


local function job_create_meta(job)
    local meta = job.meta
    local callstack = meta.callstack
    local base = 4

    for i = 1, 3 do
        local info = debug_getinfo(i + base, "nSl")

        if not info or info.short_src == "[C]" then
            break
        end

        callstack[i] = {
            line = info.currentline,
            func = info.name or info.what,
            source = info.short_src
        }
    end

    local top_stack = callstack[1]

    if top_stack then
        -- like `init.lua:128:start_timer()`
        meta.name = top_stack.source .. ":" .. top_stack.line .. ":" .. top_stack.func .. "()"
    end
end


local function job_copy(self, job)
    local ret = {
        enable = true,
        cancel = false,
        running = false,
        name = job.name,
        callback = job.callback,
        delay = {
            hour = job.delay.hour,
            minute = job.delay.minute,
            second = job.delay.second,
            msec = job.delay.msec
        },
        next_pointer = {
            hour = 0,
            minute = 0,
            second = 0,
            msec = 0
        },
        once = job.once,
        args = job.args,
        stats = job.stats,
        meta = job.meta
    }

    job_re_cal_next_pointer(ret, self.wheels)

    setmetatable(ret, {
        __tostring = job_tostring
    })

    return ret
end


local function job_create(self, name, callback, delay, once, args)
    local delay_origin = delay
    local delay_hour, delay_minute, delay_second, delay_msec
    local immediately = false
    local _

    if delay ~= 0 then
        delay, delay_msec = modf(delay)
        delay_msec = delay_msec * 1000 + 10
        delay_msec = floor(delay_msec)
        delay_msec = floor(delay_msec / 100)

        delay_hour = modf(delay / 60 / 60)
        delay = delay % (60 * 60)

        delay_minute = modf(delay / 60)
        delay_second = delay % 60

        if delay_msec == 10 then
            delay_second = delay_second + 1
            delay_msec = nil
        end

        if delay_second == 0 then
            if delay_hour == 0 and delay_minute == 0 then
                delay_second = nil
            end
        end

        if delay_minute == 0 then
            if delay_hour == 0 then
                delay_minute = nil
            end
        end

        if delay_hour == 0 then
            delay_hour = nil
        end

    else
        immediately = true
    end



    local ret = {
        enable = true,
        cancel = false,
        running = false,
        immediately = immediately,
        name = name,
        callback = callback,
        delay = {
            origin = delay_origin,
            hour = delay_hour,
            minute = delay_minute,
            second = delay_second,
            msec = delay_msec
        },
        next_pointer = {
            hour = 0,
            minute = 0,
            second = 0,
            msec = 0
        },
        once = once,
        args = args,
        stats = {
            runtime = {
                avg = 0,
                max = -1,
                min = huge,
                variance = 0
            },

            runs = 0,
            finish = 0,
            last_err_msg = ""
        },
        meta = {
            name = "[C]",
            callstack = {}
        }
    }

    job_create_meta(ret)

    if not immediately then
        job_re_cal_next_pointer(ret, self.wheels)
    end

    setmetatable(ret, {
        __tostring = job_tostring
    })

    return ret
end


local function job_wrapper(job)
    local stats = job.stats
    local runtime = stats.runtime
    stats.runs = stats.runs + 1
    local start = now()

    if not job_is_runable(job) then
        return
    end

    job.running = true

    local ok, err = pcall(job.callback, false, unpack(job.args))

    local finish = stats.finish

    if ok then
        finish = finish + 1

    else
        stats.last_err_msg = err
    end

    job.running = false
    stats.finish = finish

    if FOCUS_UPDATE_TIME then
        update_time()
    end

    local spend = now() - start

    runtime.max = max(runtime.max, spend)
    runtime.min = min(runtime.min, spend)

    local old_avg = runtime.avg
    runtime.avg = get_avg(spend, finish, old_avg)

    local old_variance = runtime.variance
    runtime.variance = get_variance(spend, finish, old_variance, old_avg)

end


local function wheel_init(nelt)
    local ret = {
        pointer = 1,
        nelt = nelt,
        array = {}
    }

    for i = 1, ret.nelt do
        ret.array[i] = setmetatable({ }, { __mode = "v" })
    end

    return ret
end


local function wheel_insert(wheel, pointer, job)
    assert(wheel)
    assert(wheel.array)
    assert(pointer > 0)

    local _job = wheel.array[pointer][job.name]

    if not _job or not job_is_runable(_job) then
        wheel.array[pointer][job.name] = job

    else
        return false, "already exists job"
    end

    return true, nil
end


-- local function wheel_insert_by_delay(wheel, delay, job)
--     assert(wheel)
--     assert(delay >= 0)

--     local pointer, is_pointer_back_to_start = wheel_cal_pointer(wheel, wheel.pointer, delay)

--     if not wheel.array[pointer][job.name] then
--         wheel.array[pointer][job.name] = job
--     else
--         return nil, "already exists job"
--     end

--     return true, nil
-- end


local function wheel_move_to_next(wheel)
    assert(wheel)

    local pointer, is_move_to_end = wheel_cal_pointer(wheel, wheel.pointer, 1)
    wheel.pointer = pointer

    return wheel.array[wheel.pointer], is_move_to_end
end


local function wheel_get_jobs(wheel)
    return wheel.array[wheel.pointer]
end


local function wheel_get_job_by_pointer(wheel, pointer)
    return wheel.array[pointer]
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


local function update_closet(self)
    local old_closet = self.closet
    local delay = 0
    local msec_wheel = self.wheels.msec
    local cur_msec_pointer = wheel_get_cur_pointer(msec_wheel)
    for i = 1, 9 do
        local pointer, is_move_to_start = wheel_cal_pointer(msec_wheel, cur_msec_pointer, i)

        delay = delay + 0.1

        if is_move_to_start then
            break
        end

        local jobs = wheel_get_job_by_pointer(msec_wheel, pointer)

        if not is_empty_table(jobs) then
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


    local callbacks = wheel_get_jobs(hour_wheel)

    if callbacks then
        for name, job in pairs(callbacks) do

            if job_is_runable(job) then
                local next = job.next_pointer

                if next.minute ~= 0 then
                    wheel_insert(minute_wheel, job.next_pointer.minute, job)

                elseif next.second ~= 0 then
                    wheel_insert(second_wheel, job.next_pointer.second, job)

                elseif next.msec ~= 0 then
                    wheel_insert(msec_wheel, job.next_pointer.msec, job)

                else
                    wheels.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end

    callbacks = wheel_get_jobs(minute_wheel)

    if callbacks then
        for name, job in pairs(callbacks) do

            if job_is_runable(job) then
                local next = job.next_pointer

                if next.second ~= 0 then
                    wheel_insert(second_wheel, job.next_pointer.second, job)

                elseif next.msec ~= 0 then
                    wheel_insert(msec_wheel, job.next_pointer.msec, job)

                else
                    wheels.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end

    callbacks = wheel_get_jobs(second_wheel)

    if callbacks then
        for name, job in pairs(callbacks) do

            if job_is_runable(job) then
                local next = job.next_pointer

                if next.msec ~= 0 then
                    wheel_insert(msec_wheel, job.next_pointer.msec, job)

                else
                    wheels.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end


    callbacks = wheel_get_jobs(msec_wheel)

    if callbacks then
        for name, job in pairs(callbacks) do
            if job_is_runable(job) then
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

    while float_compare(self.real_time, self.expected_time) == 1 do
        local _, continue = wheel_move_to_next(msec_wheel)

        if continue then
            _, continue = wheel_move_to_next(second_wheel)

            if continue then
                _, continue = wheel_move_to_next(minute_wheel)

                if continue then
                    _, _ = wheel_move_to_next(hour_wheel)
                end

            end
        end

        fetch_all_expired_jobs(self)
        self.expected_time =  self.expected_time + 0.1
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
        ok, err = wheel_insert(hour_wheel, job.next_pointer.hour, job)

    elseif job.next_pointer.minute ~= 0 then
        ok, err = wheel_insert(minute_wheel, job.next_pointer.minute, job)

    elseif job.next_pointer.second ~= 0 then
        ok, err = wheel_insert(second_wheel, job.next_pointer.second, job)

    elseif job.next_pointer.msec ~= 0 then
        ok, err = wheel_insert(msec_wheel, job.next_pointer.msec, job)

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
        local ok, err = semaphore_mover:wait(1)

        local is_no_pending_jobs = is_empty_table(wheels.pending_jobs)
        local is_no_ready_jobs = is_empty_table(wheels.ready_jobs)

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
        local ok, err = semaphore_worker:wait(1)

        while not is_empty_table(wheels.pending_jobs) do
            thread.counter.runs = thread.counter.runs + 1

            local job = get_a_item_from_table(wheels.pending_jobs)

            wheels.pending_jobs[job.name] = nil

            if job_is_runable(job) then
                job_wrapper(job)

                if job_is_once(job) then
                    jobs[job.name] = nil

                elseif job_is_runable(job) then
                    update_all_wheels(self)
                    job_re_cal_next_pointer(job, wheels)
                    insert_job_to_wheel(self, job)
                    wake_up_super_timer(self)
                end
            end
        end

        if not is_empty_table(wheels.ready_jobs) then
            wake_up_mover_timer(self)
        end

        if thread.counter.runs > self.opt.recreate_interval == 0 then
            thread.counter.runs = 0
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
            -- TODO : check the return value
            local ok, err = timer_at(0, worker_timer_callback, self, i)
        end
    end

    sleep(0.1)

    update_time()
    self.real_time = now()
    self.expected_time = self.real_time - 0.1

    while not exiting() and not self.destory do
        if premature then
            return
        end

        if self.enable then
            update_all_wheels(self)

            if not is_empty_table(wheels.ready_jobs) then
                wake_up_mover_timer(self)
            end

            update_closet(self)
            local closet = max(self.closet, 0.1)
            self.closet = huge
            semaphore_super:wait(closet)

        else
            sleep(0.1)
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

    local job = job_create(self, name, callback, delay, once, args)
    job_enable(job)
    jobs[name] = job

    if job.immediately then
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
        recreate_interval = options and options.recreate_interval or DEFAULT_RECREATE_INTERVAL,

        -- number of timer will be created by OpenResty API
        threads = options and options.threads or DEFAULT_THREADS,

        -- call function `ngx.update_time` every run of timer job
        fouce_update_time = options and options.fouce_update_time or DEFAULT_FOCUS_UPDATE_TIME
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

    self.semaphore_super = semaphore_module.new(0)

    self.semaphore_worker = semaphore_module.new(0)

    self.semaphore_mover = semaphore_module.new(0)

    self.wheels = {
        -- will be move to `pending_jobs` by function `mover_timer_callback`
        -- the function `fetch_all_expired_jobs` adds all expired job to this table
        ready_jobs = {},

        -- each job in this table will be run by function `worker_timer_callback`
        pending_jobs = {},

        -- 100ms per slot
        msec = wheel_init(10),

        -- 1 second per slot
        sec = wheel_init(60),

        -- 1 minute per slot
        min = wheel_init(60),

        -- 1 hour per slot
        hour = wheel_init(24),
    }

    for i = 1, self.opt.threads do
        self.threads[i] = {
            index = i,
            alive = false,
            counter = {
                -- number of runs
                runs = 0
            }
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

    if delay >= MAX_EXPIRE or (delay ~= 0 and delay < 0.1) or not self.configured then
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

    if interval >= MAX_EXPIRE or interval < 0.1 or not self.configured then
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

        if not job_is_enable(old_job) then
            return create(self, old_job.name, old_job.callback, old_job.delay.origin, old_job.once, old_job.args)

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

        if job_is_enable(job) then
            job_pause(job)

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

    job_cancel(job)
    jobs[name] = nil

    return true, nil
end


function _M:stats()
    local pending_jobs = self.wheels.pending_jobs

    local sys = {
        running = 0,
        pending = 0,
        waiting = 0
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
            last_err_msg = stats.last_err_msg
        }
    end


    return {
        sys = sys,
        timers = jobs
    }
end


return _M