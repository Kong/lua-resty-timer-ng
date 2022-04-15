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
local ngx_update_time = ngx.update_time

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
function _M:update_closest()
    local old_closest = self.closest
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
        -- when the pointer of the `msec_wheel` spins to the starting point.
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

    -- TODO: to calculate this value, a baseline is needed,
    --  i.e. the time when the super timer was last woken up.
    self.closest = delay

    return delay < old_closest
end


-- do the following things
-- * add all expired jobs from wheels to `wheels.ready_jobs`
-- * move some jobs from higher wheel to lower wheel
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

    ngx_update_time()
    self.real_time = ngx_now()

    local delta = self.real_time - self.expected_time
    delta = utils.convert_second_to_step(delta, resolution)

    lowest_wheel:spin_pointer(delta)

    self:fetch_all_expired_jobs()

    self.expected_time = self.expected_time + resolution * delta
end


-- insert a job into the wheel group
function _M:insert_job(job)
    return self.highest_wheel:insert(job)
end


function _M.new(wheel_setting, resolution)
    local self = {
        setting = wheel_setting,
        resolution = resolution,

        real_time = 0,
        expected_time = 0,

        closest = 0,

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

        wheels = utils.table_new(wheel_setting.level, 0),

        -- hour_wheel = wheel.new(constants.HOUR_WHEEL_ID,
        --                        constants.HOUR_WHEEL_SLOTS),

        -- minute_wheel = wheel.new(constants.MINUTE_WHEEL_ID,
        --                          constants.MINUTE_WHEEL_SLOTS),

        -- second_wheel = wheel.new(constants.SECOND_WHEEL_ID,
        --                          constants.SECOND_WHEEL_SLOTS),

        -- msec_wheel = wheel.new(constants.MSEC_WHEEL_ID,
        --                        constants.MSEC_WHEEL_SLOTS),
    }

    local prev_wheel = nil
    local cur_wheel

    for index, slots in ipairs(wheel_setting.slots) do
        local wheel_id = string_format("wheel#%d", index)
        cur_wheel = wheel.new(wheel_id, slots)

        if prev_wheel then
            cur_wheel:set_lower_wheel(prev_wheel)
            prev_wheel:set_higher_wheel(cur_wheel)
        end

        table_insert(self.wheels, cur_wheel)
        prev_wheel = cur_wheel
    end

    self.highest_wheel = self.wheels[#self.wheels]
    self.lowest_wheel = self.wheels[1]

    -- self.hour_wheel:set_lower_wheel(self.minute_wheel)

    -- self.minute_wheel:set_higher_wheel(self.hour_wheel)
    -- self.minute_wheel:set_lower_wheel(self.second_wheel)

    -- self.second_wheel:set_higher_wheel(self.minute_wheel)
    -- self.second_wheel:set_lower_wheel(self.msec_wheel)

    -- self.msec_wheel:set_higher_wheel(self.second_wheel)

    -- self.highest_wheel = self.hour_wheel
    -- self.lowest_wheel = self.msec_wheel

    return setmetatable(self, meta_table)
end


return _M