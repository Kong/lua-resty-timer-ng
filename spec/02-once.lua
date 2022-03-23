local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local TIMER_NAME = "TEST-TIMER-ONCE"
local TOLERANCE = 0.2
local THREADS = 10

local function helper(strategy, t, tbl, name, callback, delay, sleep_second)
    sleep_second = sleep_second or 0

    assert.has_no.errors(function ()
        local ok, _ = t:once(name, callback, delay, tbl, sleep_second)
        assert.is_true(ok)
    end)

    local expected = now() + delay

    if strategy == "callback_with_blocking_calls" then
        expected = expected + sleep_second
        sleep(delay + sleep_second + TOLERANCE)

    else
        sleep(delay + TOLERANCE)
    end

    assert.near(expected, tbl.time, TOLERANCE)
end


insulate("create a once timer with invalid arguments #fast | ", function ()
    local timer
    local empty_callback

    randomize()

    setup(function ()
        timer = require("resty.timer")
        timer:configure({ threads = THREADS })
        timer:start()

        empty_callback = function (_, ...) end
    end)

    teardown(function ()
        timer:stop()
        timer:unconfigure()
        sleep(2)
        assert.same(1, timer_running_count())
    end)

    it("delay < 0", function ()
        assert.has.errors(function ()
            timer:once(TIMER_NAME, empty_callback, -1)
        end)
    end)

    it("callback = nil", function ()
        assert.has.errors(function ()
            timer:once(TIMER_NAME, nil, 0)
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
    insulate("create a once timer #" .. strategy .. " | ", function ()
        local timer
        local tbl

        randomize()

        setup(function ()
            timer = require("resty.timer")
            timer:configure()
            timer:start()

            tbl = { time = 0 }
        end)

        teardown(function ()
            timer:stop()
            timer:unconfigure()
            sleep(10)
            assert.same(1, timer_running_count())
        end)

        before_each(function ()
            update_time()
            tbl.time = 0
        end)

        after_each(function ()
            assert.has_no.errors(function ()
                local ok, _ = timer:cancel(TIMER_NAME)
                assert.is_false(ok)
            end)
        end)

        it("delay = 0 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0, 0.2)
        end)

        it("delay = 0.1 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0.1, 0.1)
        end)

        it("delay = 0.5 #fast #only", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0.5, 0.3)
        end)

        it("delay = 0.9 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 0.9, 0.6)
        end)

        it("delay = 1 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1, 0.6)
        end)

        it("delay = 1.1 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.1, 1)
        end)

        it("delay = 1.5 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.5, 1.3)
        end)

        it("delay = 1.9 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 1.9, 1.5)
        end)

        it("delay = 2 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 2, 2)
        end)

        it("delay = 10 #fast", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 10, 5)
        end)

        it("delay = 59 #slow_1", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 59, 5)
        end)

        it("delay = 59.9 #slow_1", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 59.9, 5)
        end)

        it("delay = 60 #slow_2", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 60, 5)
        end)

        it("delay = 60.1 #slow_2", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 60.1, 5)
        end)

        it("delay = 61 #slow_3", function ()
            helper(strategy, timer, tbl, TIMER_NAME, callback, 61, 5)
        end)
    end)
end