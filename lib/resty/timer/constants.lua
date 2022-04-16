local utils = require("resty.timer.utils")

local math_modf = math.modf

local string_format = string.format

local assert = utils.assert

local _M = {
    DEFAULT_THREADS = 32,

    -- restart the thread after every 50 jobs have been run
    DEFAULT_RESTART_THREAD_AFTER_RUNS = 50,

    DEFAULT_FORCE_UPDATE_TIME = true,

    -- 100ms
    DEFAULT_RESOLUTION = 0.1,

    DEFAULT_WHEEL_SETTING = {
        level = 4,
        slots_for_each_level = {10, 60, 60, 24},
    },

    MSG_FATAL_FAILED_CREATE_NATIVE_TIMER
        = "failed to create a native timer: ",
}

-- We don't need a high accuracy.
assert(_M.DEFAULT_RESOLUTION,
    "`DEFAULT_RESOLUTION` must be greater than or equal to 0.1")


do
    local wheel_setting = _M.DEFAULT_WHEEL_SETTING

    assert(type(wheel_setting) == "table",
        "`DEFAULT_WHEEL_SETTING` must be a table")

    local level = wheel_setting.level
    local slots_for_each_level = wheel_setting.slots_for_each_level

    assert(type(level) == "number",
        "`DEFAULT_WHEEL_SETTING.level` muse be a number")

    assert(level >= 1,
        "`DEFAULT_WHEEL_SETTING.level` muse be greater than or equal to 1")

    local _, tmp = math_modf(level)

    assert(tmp == 0,
        "`DEFAULT_WHEEL_SETTING.level` muse be an integer")

    assert(type(slots_for_each_level) == "table",
        "`DEFAULT_WHEEL_SETTING.slots_for_each_level` muse be a table")

    local slots_for_each_level_length = #slots_for_each_level

    assert(level == slots_for_each_level_length,
        "`DEFAULT_WHEEL_SETTING.level`"
     .. " must be equal to "
     .. "the length of `DEFAULT_WHEEL_SETTING.slots_for_each_level`")


    for i, v in ipairs(slots_for_each_level) do
        assert(type(v) == "number",string_format(
            "`DEFAULT_WHEEL_SETTING.slots_for_each_level[%d]`"
         .. " must be a number", i))

        assert(v >= 1, string_format(
            "`DEFAULT_WHEEL_SETTING.slots_for_each_level[%d]`"
         .. "must be greater than 1", i))

        _, tmp = math_modf(v)

        assert(tmp == 0, string_format(
            "`DEFAULT_WHEEL_SETTING.slots_for_each_level[%d]`"
         .. "must be an integer", i))
    end
end

return _M