local utils = require("resty.timer.utils")

local assert = utils.assert

local _M = {
    DEFAULT_THREADS = 32,

    -- restart the thread after every 50 jobs have been run
    DEFAULT_RESTART_THREAD_AFTER_RUNS = 50,

    DEFAULT_FOCUS_UPDATE_TIME = true,

    -- 23:59:00
    MAX_EXPIRE = 23 * 60 * 60 + 59 * 60,

    -- 100ms
    RESOLUTION = 0.1,

    -- 100ms per slot
    MSEC_WHEEL_SLOTS = 10,

    -- 1 second per slot
    SECOND_WHEEL_SLOTS = 60,

    -- 1 minute per slot
    MINUTE_WHEEL_SLOTS = 60,

    -- 1 hour per slot
    HOUR_WHEEL_SLOTS = 24,
}


local meta_table = { __index = _M }

setmetatable(_M, meta_table)

return _M