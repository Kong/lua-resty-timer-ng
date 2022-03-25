local pairs = pairs
local setmetatable = setmetatable

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local now = ngx.now
local update_time = ngx.update_time

local utils_module = require("resty.timer.utils")
local wheel_module = require("resty.timer.wheel")
local constants = require("resty.timer.constants")

local assert = utils_module.assert

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
        local pointer, is_move_to_start =
            msec_wheel:cal_pointer(cur_msec_pointer, i)

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
                self.ready_jobs[name] = job
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
                    self.ready_jobs[name] = job
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
                    self.ready_jobs[name] = job
                end
            end

            callbacks[name] = nil
        end
    end


    callbacks = msec_wheel:get_jobs()

    if callbacks then
        for name, job in pairs(callbacks) do
            if job:is_runable() then
                self.ready_jobs[name] = job
            end

            callbacks[name] = nil
        end
    end
end


function _M:sync_time()
    local hour_wheel = self.hour_wheel
    local minute_wheel = self.minute_wheel
    local second_wheel = self.second_wheel
    local msec_wheel = self.msec_wheel

    self:fetch_all_expired_jobs()

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
        msec_wheel = wheel_module.new(constants.MSEC_WHEEL_SLOTS),

        -- 1 second per slot
        second_wheel = wheel_module.new(constants.SECOND_WHEEL_SLOTS),

        -- 1 minute per slot
        minute_wheel = wheel_module.new(constants.MINUTE_WHEEL_SLOTS),

        -- 1 hour per slot
        hour_wheel = wheel_module.new(constants.HOUR_WHEEL_SLOTS),
    }


    return setmetatable(self, meta_table)
end


return _M