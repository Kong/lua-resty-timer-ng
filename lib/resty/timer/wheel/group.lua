local utils = require("resty.timer.utils")
local wheel = require("resty.timer.wheel")
local constants = require("resty.timer.constants")

local pairs = pairs
local setmetatable = setmetatable

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local now = ngx.now
local update_time = ngx.update_time

local assert = utils.assert

local _M = {}

local meta_table = {
    __index = _M,
}


-- calculate how long until the next timer expires
function _M:update_closest()
    local old_closest = self.closest
    local delay = 0
    local msec_wheel = self.msec_wheel
    local cur_msec_pointer = msec_wheel:get_cur_pointer()

    -- `constants.MSEC_WHEEL_SLOTS - 1` means
    -- ignore the current slot
    for i = 1, constants.MSEC_WHEEL_SLOTS - 1 do
        local pointer, is_spin_to_start_slot =
            msec_wheel:cal_pointer(cur_msec_pointer, i)

        delay = delay + constants.RESOLUTION

        -- Scan only to the end point, not the whole wheel.
        -- why?
        -- Because there might be some jobs falling from the higher wheel
        -- when the pointer of the `msec_wheel` spins to the starting point.
        -- If the whole wheel is scanned
        -- and the result obtained is used as the sleep time of the super timer,
        -- some jobs of higher wheels may not be executed in time.
        -- This is because the super timer will only be woken up
        -- when any wheels are modified or when the semaphore timeout.
        if is_spin_to_start_slot then
            break
        end

        local jobs = msec_wheel:get_jobs_by_pointer(pointer)

        if not utils.is_empty_table(jobs) then
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
    local hour_wheel = self.hour_wheel
    local minute_wheel = self.minute_wheel
    local second_wheel = self.second_wheel
    local msec_wheel = self.msec_wheel


    local jobs = hour_wheel:get_jobs()

    if jobs then
        for name, job in pairs(jobs) do
            local next = job.next_pointer
            jobs[name] = nil

            -- if `next.minute` is equal 0,
            -- it means that this job does
            -- not need to be inserted
            -- into the `minute_wheel`.
            -- Same for `next.second` and `next.msec`

            if next.minute ~= 0 then
                minute_wheel:insert(job.next_pointer.minute, job)
                goto continue
            end

            if next.second ~= 0 then
                second_wheel:insert(job.next_pointer.second, job)
                goto continue
            end

            if next.msec ~= 0 then
                msec_wheel:insert(job.next_pointer.msec, job)
                goto continue
            end

            self.ready_jobs[name] = job

            ::continue::

        end
    end

    jobs = minute_wheel:get_jobs()

    if jobs then
        for name, job in pairs(jobs) do

            if job:is_runable() then
                local next = job.next_pointer
                jobs[name] = nil

                if next.second ~= 0 then
                    second_wheel:insert(job.next_pointer.second, job)
                    goto continue
                end

                if next.msec ~= 0 then
                    msec_wheel:insert(job.next_pointer.msec, job)
                    goto continue
                end

                self.ready_jobs[name] = job
            end

            ::continue::
        end
    end

    jobs = second_wheel:get_jobs()

    if jobs then
        for name, job in pairs(jobs) do

            if job:is_runable() then
                local next = job.next_pointer
                jobs[name] = nil

                if next.msec ~= 0 then
                    msec_wheel:insert(job.next_pointer.msec, job)
                    goto continue
                end

                self.ready_jobs[name] = job
            end

            ::continue::
        end
    end


    jobs = msec_wheel:get_jobs()

    if jobs then
        for name, job in pairs(jobs) do

            -- all jobs in the slot
            -- pointed by the `msec_wheel` pointer
            -- will be executed

            if job:is_runable() then
                self.ready_jobs[name] = job
            end

            jobs[name] = nil
        end
    end
end


function _M:sync_time()
    local hour_wheel = self.hour_wheel
    local minute_wheel = self.minute_wheel
    local second_wheel = self.second_wheel
    local msec_wheel = self.msec_wheel

    -- perhaps some jobs have expired but not been fetched
    self:fetch_all_expired_jobs()

    update_time()
    self.real_time = now()

    -- Until the difference with the real time is less than 100ms
    while utils.float_compare(self.real_time, self.expected_time) == 1 do

        -- if the pointer of a wheel spins to the starting point,
        -- then the pointer of a higher wheel should spin too.

        local _, is_spin_to_start_slot = msec_wheel:spin_pointer_one_slot()

        if is_spin_to_start_slot then
            _, is_spin_to_start_slot = second_wheel:spin_pointer_one_slot()

            if is_spin_to_start_slot then
                _, is_spin_to_start_slot = minute_wheel:spin_pointer_one_slot()

                if is_spin_to_start_slot then
                    hour_wheel:spin_pointer_one_slot()
                end

            end
        end

        self:fetch_all_expired_jobs()

        self.expected_time =  self.expected_time + constants.RESOLUTION
    end
end


-- insert a job into the wheel group
function _M:insert_job(job)
    local ok, err
    local hour_wheel = self.hour_wheel
    local minute_wheel = self.minute_wheel
    local second_wheel = self.second_wheel
    local msec_wheel = self.msec_wheel

    -- if `next.minute` is equal 0,
    -- it means that this job does
    -- not need to be inserted
    -- into the `minute_wheel`.
    -- Same for `next.second`,`next.msec`,
    -- and `next.hour`

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


function _M.new()
    local self = {
        real_time = 0,
        expected_time = 0,

        closest = 0,

        -- will be move to `pending_jobs` by function `mover_timer_callback`
        -- the function `fetch_all_expired_jobs`
        -- adds all expired job to this table
        ready_jobs = {},

        -- each job in this table will
        -- be run by function `worker_timer_callback`
        pending_jobs = {},

        -- 100ms per slot
        msec_wheel = wheel.new(constants.MSEC_WHEEL_SLOTS),

        -- 1 second per slot
        second_wheel = wheel.new(constants.SECOND_WHEEL_SLOTS),

        -- 1 minute per slot
        minute_wheel = wheel.new(constants.MINUTE_WHEEL_SLOTS),

        -- 1 hour per slot
        hour_wheel = wheel.new(constants.HOUR_WHEEL_SLOTS),
    }


    return setmetatable(self, meta_table)
end


return _M