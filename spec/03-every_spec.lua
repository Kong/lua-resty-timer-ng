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


insulate("create a every timer with invalid arguments | ", function ()
    local timer = { }
    local empty_callback

    randomize()

    lazy_setup(function ()
        timer = timer_module.new()
        local ok, _ = timer:start()
        assert.is_true(ok)

        empty_callback = function (_, ...) end
    end)

    lazy_teardown(function ()
        timer:freeze()
        timer:destroy()

        helper.wait_until(function ()
            assert.same(1, timer_running_count())
            return true
        end)

    end)

    it("callback is nil", function ()
        assert.has.errors(function ()
            timer:every(helper.TIMER_NAME_EVERT, nil, 1)
        end)
    end)

    it("callback is not a function", function ()
        assert.has.errors(function ()
            timer:every(helper.TIMER_NAME_EVERT, "", 1)
        end)
    end)


    it("interval <= 0", function ()
        assert.has.errors(function ()
            timer:every(helper.TIMER_NAME_EVERT, empty_callback, 0)
        end)

        assert.has.errors(function ()
            timer:every(helper.TIMER_NAME_EVERT, empty_callback, -1)
        end)
    end)

end)


for strategy, callback in pairs(strategies) do


insulate("create a every timer #" .. strategy .. " | ", function ()
    local timer = { }
    local tbl

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            resolution = helper.RESOLUTION,
            wheel_setting = helper.WHEEL_SETTING,
        })
        local ok, _ = timer:start()
        assert.is_true(ok)

        tbl = { time = 0 }
    end)

    lazy_teardown(function ()
        timer:freeze()
        timer:destroy()

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
            local ok, _ = timer:cancel(helper.TIMER_NAME_EVERT)
            assert.is_true(ok)
        end)
    end)

    for _, steps in ipairs(helper.steps_list_for_every_timer()) do
        local str = string_format(
            "steps = %d",
            steps
        )

        it(str, function ()
            local interval = steps * helper.RESOLUTION
            local sleep_second = interval / 2

            assert.has_no.errors(function ()
                local ok, _ =
                    timer:every(helper.TIMER_NAME_EVERT,
                                callback, interval, tbl, sleep_second)
                assert.is_truthy(ok)
            end)

            local expected = now() + interval

            if strategy == "callback_with_blocking_calls" then
                expected = expected + sleep_second
                sleep(interval + sleep_second + helper.ERROR_TOLERANCE)

            else
                sleep(interval + helper.ERROR_TOLERANCE)
            end

            assert.near(expected, tbl.time, helper.ERROR_TOLERANCE)

            tbl.time = 0
            expected = expected + interval

            if strategy == "callback_with_blocking_calls" then
                expected = expected + sleep_second
                sleep(interval + sleep_second + helper.ERROR_TOLERANCE)

            else
                sleep(interval + helper.ERROR_TOLERANCE)
            end

            assert.near(expected, tbl.time, helper.ERROR_TOLERANCE)
        end) -- end of `it`

    end -- end of the second loop

end) -- end of the top `insulate`


end -- end of the top loop