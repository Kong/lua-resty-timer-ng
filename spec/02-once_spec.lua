local timer_module = require("resty.timer")
local helper = require("helper")

local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count
local string_format = string.format


local callback_with_blocking_calls = function(_, tbl, sleep_second, ...)
    if sleep_second and sleep_second > 0 then
        sleep(sleep_second)
    end

    update_time()
    tbl.time = now()
end

local callback_without_blocking_calls = function(_, tbl, ...)
    update_time()
    tbl.time = now()
end


local strategies = {
    callback_with_blocking_calls = callback_with_blocking_calls,
    callback_without_blocking_calls = callback_without_blocking_calls
}


insulate("create a once timer with invalid arguments | ", function ()
    local timer = { }
    local empty_callback

    randomize()

    lazy_setup(function ()
        timer_module.configure(timer)
        timer_module.start(timer)

        empty_callback = function (_, ...) end
    end)

    lazy_teardown(function ()
        timer_module.freeze(timer)
        timer_module.unconfigure(timer)

        helper.wait_until(function ()
            assert.same(1, timer_running_count())
            return true
        end)

    end)

    it("delay < 0", function ()
        assert.has.errors(function ()
            timer:once(helper.TIMER_NAME_ONCE, empty_callback, -1)
        end)
    end)

    it("callback = nil", function ()
        assert.has.errors(function ()
            timer:once(helper.TIMER_NAME_ONCE, nil, 0)
        end)
    end)

end)


for strategy, callback in pairs(strategies) do


insulate("create a once timer #" .. strategy .. " | ", function ()
    local timer = { }
    local tbl

    randomize()

    lazy_setup(function ()
        timer_module.configure(timer, {
            resolution = helper.RESOLUTION,
            wheel_setting = helper.WHEEL_SETTING,
        })
        timer_module.start(timer)

        tbl = { time = 0 }
    end)

    lazy_teardown(function ()
        timer_module.freeze(timer)
        timer_module.unconfigure(timer)

        helper.wait_until(function ()
            assert.same(1, timer_running_count())
            return true
        end)

    end)

    before_each(function ()
        update_time()
        tbl.time = 0
    end)

    after_each(function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:cancel(helper.TIMER_NAME_ONCE)
            assert.is_false(ok)
        end)
    end)

    for _, steps in ipairs(helper.steps_list_for_once_timer()) do
        local str = string_format(
            "steps = %d",
            steps
        )

        it(str, function ()
            local delay = steps * helper.RESOLUTION
            local sleep_second = delay / 2

            assert.has_no.errors(function ()
                local ok, _ =
                    timer:once(helper.TIMER_NAME_ONCE,
                                callback, delay, tbl, sleep_second)
                assert.is_truthy(ok)
            end)

            local expected = now() + delay

            if strategy == "callback_with_blocking_calls" then
                expected = expected + sleep_second
                sleep(delay + sleep_second + helper.ERROR_TOLERANCE)

            else
                sleep(delay + helper.ERROR_TOLERANCE)
            end

            assert.near(expected, tbl.time, helper.ERROR_TOLERANCE)
        end)
    end
end)


end