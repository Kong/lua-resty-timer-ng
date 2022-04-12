local timer_module = require("resty.timer")


local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local TIMER_NAME = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2
local THREADS = 10

local function helper(strategy, t, tbl, name, callback, interval, sleep_second)
    sleep_second = sleep_second or 0

    assert.has_no.errors(function ()
        local ok, _ = t:every(name, callback, interval, tbl, sleep_second)
        assert.is_true(ok)
    end)

    local expected = now() + interval

    if strategy == "callback_with_blocking_calls" then
        expected = expected + sleep_second
        sleep(interval + sleep_second + TOLERANCE)

    else
        sleep(interval + TOLERANCE)
    end

    assert.near(expected, tbl.time, TOLERANCE)

    tbl.time = 0

    expected = expected + interval

    if strategy == "callback_with_blocking_calls" then
        expected = expected + sleep_second
        sleep(interval + sleep_second + TOLERANCE)

    else
        sleep(interval + TOLERANCE)
    end

    assert.near(expected, tbl.time, TOLERANCE)
end


insulate("create a every timer with invalid arguments #fast | ", function ()
    local timer = { }
    local empty_callback

    randomize()

    lazy_setup(function ()
        timer_module.configure(timer, { threads = THREADS })
        timer_module.start(timer)

        empty_callback = function (_, ...) end
    end)

    lazy_teardown(function ()
        timer_module.freeze(timer)
        timer_module.unconfigure(timer)
        sleep(2)
        assert.same(1, timer_running_count())
    end)

    it("callback is nil", function ()
        assert.has.errors(function ()
            timer:every(TIMER_NAME, nil, 1)
        end)
    end)

    it("callback is not a function", function ()
        assert.has.errors(function ()
            timer:every(TIMER_NAME, "", 1)
        end)
    end)


    it("interval <= 0", function ()
        assert.has.errors(function ()
            timer:every(TIMER_NAME, empty_callback, 0)
        end)

        assert.has.errors(function ()
            timer:every(TIMER_NAME, empty_callback, -1)
        end)
    end)


end)


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


for strategy, callback in pairs(strategies) do
    insulate("create a every timer #" .. strategy .. " | ", function ()
        local timer = { }
        local tbl

        randomize()

        lazy_setup(function ()
            timer_module.configure(timer, { threads = THREADS })
            timer_module.start(timer)

            tbl = {
                time = 0
            }
        end)

        lazy_teardown(function ()
            timer_module.freeze(timer)
            timer_module.unconfigure(timer)
            sleep(10)
            assert.same(1, timer_running_count())
        end)

        before_each(function ()
            update_time()
            tbl.time = 0
        end)

        after_each(function ()
            local ok, _ = timer:cancel(TIMER_NAME)
            assert.is_true(ok)
        end)

        -- it("interval = 0.1 #fast", function ()
        --     helper(strategy, timer, tbl, TIMER_NAME, callback, 0.1, 0)
        -- end)

        it("interval = 0.5 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0.5, 0.4)
        end)

        it("interval = 0.9 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0.9, 0.5)
        end)

        it("interval = 1 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1, 0.5)
        end)

        it("interval = 1.1 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.1, 0.5)
        end)

        it("interval = 1.5 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.5, 1)
        end)

        it("interval = 1.9 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.9, 1)
        end)

        it("interval = 2 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 2, 1)
        end)

        it("interval = 10 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 10, 5)
        end)

        it("interval = 59 #slow_1", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 59, 5)
        end)

        it("interval = 59.9 #slow_2", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 59.9, 5)
        end)

        it("interval = 60 #slow_3", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 60, 5)
        end)

        it("interval = 60.1 #slow_4", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 60.1, 5)
        end)

        it("interval = 61 #slow_5", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 61, 5)
        end)
    end)
end