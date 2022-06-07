local ngx_sleep = ngx.sleep
local ngx_update_time = ngx.update_time
local ngx_now = ngx.now
local string_format = string.format
local table_insert = table.insert
local math_max = math.max

local _M = {
    ROUND = tonumber(os.getenv("TIMER_SPEC_TEST_ROUND")) or 6,

    RESOLUTION = 0.1,

    TIMER_NAME_ONCE = "TEST-TIMER-ONCE",
    TIMER_NAME_EVERT = "TEST-TIMER-EVERY",

    ERROR_TOLERANCE = 0.2,

    WHEEL_SETTING = {
        level = 3,
        slots_for_each_level = {
            3, 3, 5,
        },
    }
}


do
    local max_steps = 0

    for _, slots in ipairs(_M.WHEEL_SETTING.slots_for_each_level) do
        max_steps = max_steps + slots
    end

    _M.MAX_STEPS = max_steps
    _M.max_EXPIRE = max_steps * _M.RESOLUTION
end


function _M.convert_steps_to_second(steps)
    return steps * _M.RESOLUTION
end


function _M.steps_list_for_once_timer()
    local steps = {}

    for _ = 1, math_max(_M.ROUND, 2) do
        for step = 0, _M.MAX_STEPS do
            table_insert(steps, step)
        end
    end

    return steps
end


function _M.steps_list_for_every_timer()
    local steps = {}

    for _ = 1, math_max(_M.ROUND / 2, 2) do
        for step = 5, _M.MAX_STEPS do
            table_insert(steps, step)
        end
    end

    return steps
end


function _M.wait_until(callback, timeout)
    local step = 0.15
    timeout = timeout and timeout or 10

    ngx_update_time()
    local max_wait = ngx_now() + timeout

    local ok, true_or_false_or_err, err
    repeat
        ok, true_or_false_or_err, err = pcall(callback)
        ngx_sleep(step)
        ngx_update_time()
    until ok or true_or_false_or_err == true or ngx_now() > max_wait

    if not ok then
        error(tostring(true_or_false_or_err), 2)
        return
    end

    if true_or_false_or_err == false and err then
        local err_msg = string_format(
            "wait_until() timeout: %s (after delay %fs)",
            tostring(err), timeout
        )
        error(err_msg, 2)
        return
    end

    if true_or_false_or_err == false then
        local err_msg = string_format(
            "wait_until() timeout (after delay %fs)",
            timeout
        )
        error(err_msg, 2)
        return
    end
end

return _M