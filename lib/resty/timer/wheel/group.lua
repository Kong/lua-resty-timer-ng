local utils = require("resty.timer.utils")
local wheel = require("resty.timer.wheel")

local table_insert = table.insert

local string_format = string.format

local ngx = ngx

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
-- luacheck: pop

local ngx_now = ngx.now

local ipairs = ipairs
local setmetatable = setmetatable

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local _M = {}

local meta_table = {
    __index = _M,
}


-- calculate how long until the next timer expires
function _M:get_closest()
    local delay = 0
    local lowest_wheel = self.lowest_wheel
    local resolution = self.resolution
    local cur_msec_pointer = lowest_wheel:get_cur_pointer()

    -- `lowest_wheel.nelts - 1` means
    -- ignore the current slot
    for i = 1, lowest_wheel.nelts do
        local pointer, cycles =
            lowest_wheel:cal_pointer(cur_msec_pointer, i)

        delay = delay + resolution

        -- Scan only to the end point, not the whole wheel.
        -- why?
        -- Because there might be some jobs falling from the higher wheel
        -- when the pointer of the `lowest_wheel` spins to the starting point.
        -- If the whole wheel is scanned
        -- and the result obtained is used as the sleep time of the super timer,
        -- some jobs of higher wheels may not be executed in time.
        -- This is because the super timer will only be woken up
        -- when any wheels are modified or when the semaphore timeout.
        if cycles ~= 0 then
            break
        end

        local jobs = lowest_wheel:get_jobs_by_pointer(pointer)

        if not utils.table_is_empty(jobs) then
            break
        end
    end

    return delay
end


-- do the following things
-- * add all expired jobs from wheels to `wheels.ready_jobs`
function _M:fetch_all_expired_jobs()
    for _, _wheel in ipairs(self.wheels) do
        utils.table_merge(self.ready_jobs, _wheel:fetch_all_expired_jobs())
    end
end


function _M:sync_time()
    local lowest_wheel = self.lowest_wheel
    local resolution = self.resolution

    -- perhaps some jobs have expired but not been fetched
    self:fetch_all_expired_jobs()

    -- This function will cause a system call
    -- and is not called for performance reasons.
    -- In theory, doing so would cause a potential bug.
    -- For example:
        -- timer:once(...)
        -- performing time-consuming arithmetic operations
        -- timer:once(...)
    -- We know that the time cache of Nginx
    -- is updated every time we sleep or yield.
    -- But if this arithmetic operation takes a long time,
    -- for example, three seconds,
    -- then the time we obtained is not correct.
    -- However, this practice is not recommended,
    -- so it is not handled.
    -- ngx.update_time()

    self.real_time = ngx_now()

    if utils.float_compare(self.real_time, self.expected_time) <= 0 then
        -- This could be caused by a floating-point error
        -- or by NTP changing the time to an earlier time.
        return
    end

    local delta = self.real_time - self.expected_time
    local steps = utils.convert_second_to_step(delta, resolution)

    lowest_wheel:spin_pointer(steps)

    self:fetch_all_expired_jobs()

    -- The floating-point error may cause
    -- `expected_time` to be larger than `real_time`
    -- after this line is run.
    self.expected_time = self.expected_time + resolution * steps
end


-- insert a job into the wheel group
function _M:insert_job(job)
    return self.highest_wheel:insert(job)
end


function _M.new(wheel_setting, resolution)
    local self = {
        -- see `constants.DEFAULT_WHEEL_SETTING`
        setting = wheel_setting,

        -- see `constants.DEFAULT_RESOLUTION`
        resolution = resolution,

        -- get it by `ngx.now()`
        real_time = 0,

        -- time of last update of wheel-group status
        expected_time = 0,

        -- Why use two queues?
        -- Because a zero-delay timer may create another zero-delay timer,
        -- and all zero-delay timers will be
        -- inserted directly into the queue,
        -- at which point it will cause the queue to never be empty.

        -- will be move to `pending_jobs` by function `mover_timer_callback`
        -- the function `fetch_all_expired_jobs`
        -- adds all expired job to this table
        -- TODO: use `utils.table_new`
        ready_jobs = {},

        -- each job in this table will
        -- be run by function `worker_timer_callback`
        -- TODO: use `utils.table_new`
        pending_jobs = {},

        -- store wheels for each level
        -- map from wheel_level to wheel
        wheels = utils.table_new(wheel_setting.level, 0),
    }

    local prev_wheel = nil
    local cur_wheel

    -- connect all the wheels to make a group, like a clock.
    for level, slots in ipairs(wheel_setting.slots_for_each_level) do
        local wheel_id = string_format("wheel#%d", level)
        cur_wheel = wheel.new(wheel_id, slots)

        if prev_wheel then
            cur_wheel:set_lower_wheel(prev_wheel)
            prev_wheel:set_higher_wheel(cur_wheel)
        end

        table_insert(self.wheels, cur_wheel)
        prev_wheel = cur_wheel
    end

    -- the highest wheels was used to insert jobs
    self.highest_wheel = self.wheels[#self.wheels]

    -- the lowest wheel was used to reschedule jobs
    self.lowest_wheel = self.wheels[1]

    return setmetatable(self, meta_table)
end


return _M