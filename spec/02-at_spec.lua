local timer_module = require("resty.timerng")
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
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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

    it("delay < 0", function ()
        assert.has.errors(function ()
            timer:named_at(helper.TIMER_NAME_ONCE, -1, empty_callback)
        end)
    end)

    it("callback = nil", function ()
        assert.has.errors(function ()
            timer:named_at(helper.TIMER_NAME_ONCE, 0, nil)
        end)
    end)

end)


for strategy, callback in pairs(strategies) do


insulate("create a once timer #" .. strategy .. " | ", function ()
    local timer = { }
    local tbl

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            resolution = helper.RESOLUTION,
            wheel_setting = helper.WHEEL_SETTING,
            min_threads = 16,
            max_threads = 32,
        })

        assert(timer:start())

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
            timer:cancel(helper.TIMER_NAME_ONCE)
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
                assert(
                    timer:named_at(helper.TIMER_NAME_ONCE,
                                   delay, callback, tbl, sleep_second)
                )
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