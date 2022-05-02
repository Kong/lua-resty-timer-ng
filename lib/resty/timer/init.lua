local job_module = require("resty.timer.job")
local utils = require("resty.timer.utils")
local wheel_group = require("resty.timer.wheel.group")
local constants = require("resty.timer.constants")
local thread_group = require("resty.timer.thread.group")

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

local utils_float_compare = utils.float_compare
local utils_table_deepcopy = utils.table_deepcopy

local math_floor = math.floor
local math_modf = math.modf

local string_format = string.format

local ngx_timer_at = ngx.timer.at
local ngx_timer_every = ngx.timer.every
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time

local table_insert = table.insert

local pairs = pairs
local ipairs = ipairs
local type = type
local select = select

local TIMER_ONCE = true
local TIMER_REPEATED = false

local _M = {}


---create a timed task and insert it into the wheel group
---@param self table self
---@param name any name of this timer
---@param callback function callback of this timer
---@param delay number how many seconds to expire
---@param timer_type boolean TIMER_ONCE or TIMER_REPEATED
---@param argc integer the number of arguments to the callback function
---@param argv table arguments to the callback function
---@return boolean name_or_false the name of the timer if ok, otherwise false
---@return string err error message
local function create(self, name, callback, delay, timer_type, argc, argv)
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
                               timer_type, argc, argv)
    job:enable()
    jobs[name] = job
    self.counter.total = self.counter.total + 1

    if job:is_immediate() then
        table_insert(wheels.ready_jobs, job)
        self.thread_group:woke_up_mover_thread()

        return name, nil
    end

    local ok, err = wheels:insert_job(job)

    self.thread_group:wake_up_super_thread()

    if ok then
        return name, nil
    end

    return false, err
end


function _M.new(options)
    local timer_sys = {}

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

            assert(utils_float_compare(options.resolution, 0.1) >= 0,
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

    timer_sys.thread_group = thread_group.new(timer_sys)

    timer_sys.jobs = {}

    timer_sys.is_first_start = true

    timer_sys.wheels = wheel_group.new(opt.wheel_setting, opt.resolution)

    timer_sys.counter = {
        runs = 0,
        running = 0,
        total = 0,
    }

    return setmetatable(timer_sys, { __index = _M })
end


function _M:start()
    if self.is_first_start then
        local ok, err = self.thread_group:spawn()

        if not ok then
            return false, "failed to spawn threads: " .. err
        end

        self.is_first_start = false
    end

    if not self.enable then
        ngx_update_time()
        self.wheels.expected_time = ngx_now()
    end

    self.enable = true

    return true, nil
end


function _M:freeze()
    self.enable = false
end


-- TODO: rename this method
function _M:destroy()
    self.thread_group:kill()
end


function _M:once(name, delay, callback, ...)
    assert(self.enable, "the timer module is not started")
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(delay) == "number", "expected `delay to be a number")
    assert(delay >= 0, "expected `delay` to be greater than or equal to 0")

    if delay >= self.max_expire
        or (delay ~= 0 and delay < self.opt.resolution)
    then

        local log = string_format(
                        "[timer] fallback to ngx.timer.at [delay = %f]",
                        delay)

        ngx_log(ngx_NOTICE, log)

        return ngx_timer_at(delay, callback, ...)
    end

    -- TODO: desc the logic and add related tests
    local name_or_false, err =
        create(self, name, callback, delay,
               TIMER_ONCE, select("#", ...), { ... })

    return name_or_false, err
end


function _M:every(name, interval, callback, ...)
    assert(self.enable, "the timer module is not started")
    assert(type(callback) == "function", "expected `callback` to be a function")

    assert(type(interval) == "number", "expected `interval to be a number")
    assert(interval > 0, "expected `interval` to be greater than or equal to 0")

    if interval >= self.max_expire
        or interval < self.opt.resolution then

        local log = string_format(
                        "[timer] fallback to ngx.timer.every [interval = %f]",
                        interval)

        ngx_log(ngx_NOTICE, log)

        return ngx_timer_every(interval, callback, ...)
    end

    local name_or_false, err =
        create(self, name, callback, interval,
               TIMER_REPEATED, select("#", ...), { ... })

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
    self.counter.total = self.counter.total - 1

    return true, nil
end


function _M:is_managed(name)
    return self.jobs[name] ~= nil
end


function _M:stats()
    local pending_jobs = self.wheels.pending_jobs
    local ready_jobs = self.wheels.ready_jobs

    local sys = {
        running = self.counter.running,
        pending = #pending_jobs + #ready_jobs,
        waiting = nil,
        total = self.counter.total,
        runs = self.counter.runs,
    }

    sys.waiting = sys.total - sys.running - sys.pending

    -- TODO: use `utils.table_new`
    local jobs = {}

    for name, job in pairs(self.jobs) do
        local stats = job.stats
        jobs[name] = {
            name = name,
            meta = job:get_metadata(),
            elapsed_time = utils_table_deepcopy(job.stats.elapsed_time),
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