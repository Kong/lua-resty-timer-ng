local semaphore = require("ngx.semaphore")
local job_module = require("resty.timer.job")
local utils = require("resty.timer.utils")
local wheel_group = require("resty.timer.wheel.group")
local constants = require("resty.timer.constants")
local thread = require("resty.timer.thread")

local ngx = ngx

local math_floor = math.floor
local math_modf = math.modf
local math_abs = math.abs
local math_min = math.min
local math_max = math.max

local string_format = string.format

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local ngx_NOTICE = ngx.NOTICE
-- luacheck: pop

local ngx_timer_at = ngx.timer.at
local ngx_timer_every = ngx.timer.every
local ngx_sleep = ngx.sleep
local ngx_now = ngx.now

local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local type = type
local next = next
local select = select

local assert = utils.assert

local _M = {}


local function create_all_threads_atomic(self, timeout)
    local super_thread = self.super_thread
    local mover_thread = self.mover_thread
    local worker_threads = self.worker_threads

    local ok, err = super_thread:spawn()

    if not ok then
        return false, "failed to create thread: " .. err
    end

    ok, err = mover_thread:spawn()

    if not ok then
        local okk, errr = super_thread:kill(timeout)

        if okk then
            return false, "failed to create thread: " .. err
        end

        err = string_format("failed to create thread: %s"
                         .. ", falied to destroy previous: %s",
                            err, errr)

        return false, err
    end

    local worker_thread_index = 1

    while worker_thread_index <= #worker_threads do
        ok, err = worker_threads[worker_thread_index]:spawn()

        if not ok then
            break
        end

        worker_thread_index = worker_thread_index + 1
    end

    if ok then
        return true, nil
    end

    for i = 1, worker_thread_index do
        local okk, errr = worker_threads[i]:kill(timeout)

        if not okk then
            err = string_format("failed to create thread: %s"
            .. ", falied to destroy previous: %s",
               err, errr)

            return false, err
        end
    end

    return false, "failed to create thread: " .. err
end


local function kill_all_threads(self, timeout)
    local super_thread = self.super_thread
    local mover_thread = self.mover_thread
    local worker_threads = self.worker_threads

    local ok, err = super_thread:kill(timeout)

    if not ok then
        return false, "failed to kill thread: " .. err
    end

    ok, err = mover_thread:kill(timeout)

    if not ok then
        return false, "failed to kill thread: " .. err
    end

    for i = 1, #worker_threads do
        ok, err = worker_threads[i]:kill(timeout)

        if not ok then
            return false, "failed to kill thread: " .. err
        end

    end

    return true, nil
end


---post some resources until `self.semaphore_super:count() == 1`
---@TODO: rename the first argument ?
local function wake_up_super_timer(self)
    local semaphore_super = self.semaphore_super

    local count = semaphore_super:count()

    if count <= 0 then
        semaphore_super:post(math_abs(count) + 1)
    end
end


---post some resources until `self.semaphore_mover:count() == 1`
---@TODO: rename the first argument ?
local function wake_up_mover_timer(self)
    local semaphore_mover = self.semaphore_mover

    local count = semaphore_mover:count()

    if count <= 0 then
        semaphore_mover:post(math_abs(count) + 1)
    end
end


---move all jobs from `self.wheels.ready_jobs` to `self.wheels.pending_jobs`
---and wake up all worker timers
local function mover_timer_callback(self)
    local semaphore_worker = self.semaphore_worker
    local semaphore_mover = self.semaphore_mover
    local opt_threads = self.opt.threads
    local wheels = self.wheels

    local ok, err =
        semaphore_mover:wait(constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR, "failed to wait on `semaphore_mover`: " .. err)
    end

    local is_no_pending_jobs =
        utils.table_is_empty(wheels.pending_jobs)

    local is_no_ready_jobs =
        utils.table_is_empty(wheels.ready_jobs)

    if not is_no_pending_jobs then
        semaphore_worker:post(opt_threads)
        return
    end

    if not is_no_ready_jobs then
        -- just swap two lists
        -- `wheels.ready_jobs = {}` will bring work to GC
        local temp = wheels.pending_jobs
        wheels.pending_jobs = wheels.ready_jobs
        wheels.ready_jobs = temp

        semaphore_worker:post(opt_threads)
    end
end


-- exec all expired jobs
-- re-insert the recurrent job
-- delete once job from `self.jobs`
-- wake up the super timer
local function worker_timer_callback(self, thread_index)
    local semaphore_worker = self.semaphore_worker
    local wheels = self.wheels
    local jobs = self.jobs

    local ok, err =
        semaphore_worker:wait(constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

    if not ok and err ~= "timeout" then
        ngx_log(ngx_ERR, string_format(
            "failed to wait on `semaphore_worker` in thread #%d: %s",
            thread_index, err))
    end

    local _, job = next(wheels.pending_jobs)

    if not job then
        if not utils.table_is_empty(wheels.ready_jobs) then
            wake_up_mover_timer(self)
        end

        return
    end

    wheels.pending_jobs[job.name] = nil

    if not job:is_runnable() then
        return
    end

    job:execute()

    if job:is_oneshot() then
        jobs[job.name] = nil
        return
    end

    if job:is_runnable() then
        wheels:sync_time()
        job:re_cal_next_pointer(wheels)
        wheels:insert_job(job)
        wake_up_super_timer(self)
    end

end


-- do the following things
-- * create all worker timer
-- * wake up mover timer
-- * update the status of all wheels
-- * calculate wait time for `semaphore_super`
local function super_timer_callback(self)
    local semaphore_super = self.semaphore_super
    local opt_resolution = self.opt.resolution
    local wheels = self.wheels

    if self.enable then
        -- update the status of the wheel group
        wheels:sync_time()

        if not utils.table_is_empty(wheels.ready_jobs) then
            wake_up_mover_timer(self)
        end

        local closest = wheels:get_closest()

        closest = math_max(closest, opt_resolution)
        closest = math_min(closest,
                            constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)

        local ok, err = semaphore_super:wait(closest)

        if not ok and err ~= "timeout" then
            ngx_log(ngx_ERR, "failed to wait on `semaphore_super`: " .. err)
        end

    else
        ngx_sleep(constants.MIN_RESOLUTION)
    end
end


local function create(self, name, callback, delay, once, argc, argv)
    local wheels = self.wheels
    local jobs = self.jobs
    if not name then
        name = string_format("unix_timestamp=%f;counter=%d",
                             math_floor(ngx_now() * 1000),
                             self.id_counter)
        self.id_counter = self.id_counter + 1
    end

    if jobs[name] then
        return false, "already exists timer"
    end

    wheels:sync_time()

    local job = job_module.new(wheels, name,
                               callback, delay,
                               once, argc, argv)
    job:enable()
    jobs[name] = job

    if job:is_immediate() then
        wheels.ready_jobs[name] = job
        wake_up_mover_timer(self)

        return true, nil
    end

    local ok, err = wheels:insert_job(job)

    wake_up_super_timer(self)

    if ok then
        return name, nil
    end

    return false, err
end


function _M.new(options)
    local timer_sys = {}
    local err

    if options then
        assert(type(options) == "table", "expected `options` to be a table")

        if options.restart_thread_after_runs then
            assert(type(options.restart_thread_after_runs) == "number",
                "expected `restart_thread_after_runs` to be a number")

            assert(options.restart_thread_after_runs > 0,
                "expected `restart_thread_after_runs` to be greater than 0")

            local _, tmp = math_modf(options.restart_thread_after_runs)

            assert(tmp == 0,
                "expected `restart_thread_after_runs` to be an integer")
        end

        if options.threads then
            assert(type(options.threads) == "number",
                "expected `threads` to be a number")

            assert(options.threads > 0,
            "expected `threads` to be greater than 0")

            local _, tmp = math_modf(options.threads)
            assert(tmp == 0, "expected `threads` to be an integer")
        end

        if options.resolution then
            assert(type(options.resolution) == "number",
                "expected `resolution` to be a number")

            assert(utils.float_compare(options.resolution, 0.1) >= 0,
            "expected `resolution` to be greater than or equal to 0.1")
        end

        if options.wheel_setting then
            local wheel_setting = options.wheel_setting
            local level = wheel_setting.level

            assert(type(wheel_setting) == "table",
                "expected `wheel_setting` to be a table")

            assert(type(wheel_setting.level) == "number",
                "expected `wheel_setting.level` to be a number")

            assert(type(wheel_setting.slots_for_each_level) == "table",
                "expected `wheel_setting.slots_for_each_level` to be a table")

            local slots_for_each_level_length =
                #wheel_setting.slots_for_each_level

            assert(level == slots_for_each_level_length,
                "expected `wheel_setting.level`"
             .. " is equal to "
             .. "the length of `wheel_setting.slots_for_each_level`")

            for i, v in ipairs(wheel_setting.slots_for_each_level) do
                if type(v) ~= "number" then
                    error(string_format(
                        "expected"
                     .. " `wheel_setting.slots_for_each_level[%d]` "
                     .. "to be a number",
                        i))
                end

                if v < 1 then
                    error(string_format(
                        "expected"
                     .. " `wheel_setting.slots_for_each_level[%d]` "
                     .. "to be greater than 1",
                        i))
                end

                if v ~= math_floor(v) then
                    error(string_format(
                        "expected `wheel_setting.slots_for_each_level[%d]`"
                     .. " to be an integer", i))
                end
            end

        end
    end

    local opt = {
        wheel_setting = options
            and options.wheel_setting
            or constants.DEFAULT_WHEEL_SETTING,

        resolution = options
            and options.resolution
            or  constants.DEFAULT_RESOLUTION,

        -- restart the thread after every n jobs have been run
        restart_thread_after_runs = options
            and options.restart_thread_after_runsor
            or constants.DEFAULT_RESTART_THREAD_AFTER_RUNS,

        -- number of timer will be created by OpenResty API
        threads = options
            and options.threads
            or constants.DEFAULT_THREADS,

        -- call function `ngx.update_time` every run of timer job
        force_update_time = options
            and options.force_update_time
            or constants.DEFAULT_FORCE_UPDATE_TIME,
    }

    timer_sys.opt = opt

    -- to generate some IDs
    timer_sys.id_counter = 0

    timer_sys.max_expire = opt.resolution
    for _, v in ipairs(opt.wheel_setting.slots_for_each_level) do
        timer_sys.max_expire = timer_sys.max_expire * v
    end
    timer_sys.max_expire = timer_sys.max_expire - 2

    -- enable/diable entire timing system
    timer_sys.enable = false

    timer_sys.super_thread = thread.new("super",
                                        opt.restart_thread_after_runs * 100,
                                        super_timer_callback,
                                        timer_sys)

    timer_sys.mover_thread = thread.new("mover",
                                        opt.restart_thread_after_runs * 100,
                                        mover_timer_callback,
                                        timer_sys)

    timer_sys.worker_threads = {}

    timer_sys.jobs = {}

    timer_sys.is_all_threads_created = false

    timer_sys.semaphore_super, err = semaphore.new()
    assert(timer_sys.semaphore_super,
        "failed to create a semaphore: " .. tostring(err))

    timer_sys.semaphore_worker, err = semaphore.new()
    assert(timer_sys.semaphore_worker,
        "failed to create a semaphore: " .. tostring(err))

    timer_sys.semaphore_mover, err = semaphore.new()
    assert(timer_sys.semaphore_mover,
        "failed to create a semaphore: " .. tostring(err))

    timer_sys.wheels = wheel_group.new(opt.wheel_setting, opt.resolution)

    for i = 1, timer_sys.opt.threads do
        timer_sys.worker_threads[i] = thread.new(
            string_format("worker#%d", i),
            opt.restart_thread_after_runs,
            worker_timer_callback,
            timer_sys,
            i
        )
    end

    return setmetatable(timer_sys, { __index = _M })
end


function _M:start()
    local ok, err

    if not self.is_all_threads_created then
        ok, err = create_all_threads_atomic(self, 5)

        if not ok then
            return err, "falied to start: " .. err
        end

        self.is_all_threads_created = true
    end

    self.wheels.expected_time = nil
    self.enable = true

    return true, nil
end


function _M:freeze()
    self.enable = false
end


-- TODO: rename this method
function _M:destroy()
    if not self.is_all_threads_created then
        return true, nil
    end

    local ok, err = kill_all_threads(self, 5)

    if not ok then
        return false, "failed to destroy: " .. err
    end

    return true, nil
end



function _M:once(name, callback, delay, ...)
    assert(self.enable, "the timer module is not started")
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(delay) == "number", "expected `delay to be a number")
    assert(delay >= 0, "expected `delay` to be greater than or equal to 0")

    if delay >= self.max_expire
        or (delay ~= 0 and delay < self.opt.resolution)
    then

        ngx_log(ngx_NOTICE,
                "fallback to ngx.timer.every [delay = "
                .. delay .. "]")

        local ok, err = ngx_timer_at(delay, callback, ...)
        return ok ~= nil, err
    end

    -- TODO: desc the logic and add related tests
    local name_or_false, err =
        create(self, name, callback, delay,
               true, select("#", ...), { ... })

    return name_or_false, err
end


function _M:every(name, callback, interval, ...)
    assert(self.enable, "the timer module is not started")
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(interval) == "number", "expected `interval to be a number")
    assert(interval > 0, "expected `interval` to be greater than or equal to 0")

    if interval >= self.max_expire
        or interval < self.opt.resolution then

        ngx_log(ngx_NOTICE,
                "fallback to ngx.timer.every [interval = "
                .. interval .. "]")

        local ok, err = ngx_timer_every(interval, callback, ...)
        return ok ~= nil, err
    end

    local name_or_false, err =
        create(self, name, callback, interval,
               false, select("#", ...), { ... })

    return name_or_false, err
end


function _M:run(name)
    assert(type(name) == "string", "expected `name` to be a string")

    local jobs = self.jobs
    local old_job = jobs[name]

    if not old_job then
        return false, "timer not found"
    end

    jobs[name] = nil

    if old_job:is_runnable() then
        return false, "running"
    end

    local name_or_false, err =
        create(self, old_job.name, old_job.callback,
               old_job.delay, old_job:is_oneshot(),
               old_job.argc, old_job.argv)

    local ok = name_or_false ~= false

    jobs[name].meta = old_job:get_metadata()

    return ok, err
end


function _M:pause(name)
    assert(type(name) == "string", "expected `name` to be a string")

    local jobs = self.jobs
    local job = jobs[name]

    if not job then
        return false, "timer not found"
    end

    job:pause()

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
    local ready_jobs = self.wheels.ready_jobs

    local sys = {
        running = 0,
        pending = 0,
        waiting = 0,
    }

    -- TODO: use `utils.table_new`
    local jobs = {}

    for name, job in pairs(self.jobs) do
        if job.running then
            sys.running = sys.running + 1

        elseif pending_jobs[name] or ready_jobs[name] then
            sys.pending = sys.pending + 1

        else
            sys.waiting = sys.waiting + 1
        end

        local stats = job.stats
        jobs[name] = {
            name = name,
            meta = job:get_metadata(),
            elapsed_time = utils.table_deepcopy(job.stats.elapsed_time),
            runs = stats.runs,
            faults = stats.runs - stats.finish,
            last_err_msg = stats.last_err_msg,
        }
    end


    return {
        sys = sys,
        timers = jobs,
    }
end


return _M