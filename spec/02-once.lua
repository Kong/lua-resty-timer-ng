local sleep = ngx.sleep
local log = ngx.log
local ERR = ngx.ERR
local update_time = ngx.update_time
local now = ngx.now

local TIMER_NAME = "TEST-TIMER-ONCE"
local TOLERANCE = 0.2

local function helper(t, tbl, name, callback, delay)
    assert.has_no.errors(function ()
        local ok, _ = t:once(name, callback, delay, tbl)
        assert.is_true(ok)
    end)

    local expected = now() + delay
    sleep(delay + TOLERANCE)
    assert.near(expected, tbl.time, TOLERANCE)
end


insulate("create a once timer with invalid arguments #fast | ", function ()
    local timer
    local empty_callback

    randomize()

    setup(function ()
        timer = require("resty.timer")
        timer:configure()
        timer:start()

        empty_callback = function (_, ...) end
    end)

    teardown(function ()
        timer:stop()
        timer:unconfigure()
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



insulate("create a once timer | ", function ()
    local timer
    local callback
    local tbl

    randomize()

    setup(function ()
        timer = require("resty.timer")
        timer:configure()
        timer:start()

        tbl = {
            time = 0
        }

        callback = function (_, tbl, ...)
            update_time()
            tbl.time = now()
        end
    end)

    teardown(function ()
        timer:stop()
        timer:unconfigure()
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
        helper(timer, tbl, TIMER_NAME, callback, 0)
    end)

    it("delay = 0.1 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 0.1)
    end)

    it("delay = 0.5 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 0.5)
    end)

    it("delay = 0.9 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 0.9)
    end)

    it("delay = 1 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1)
    end)

    it("delay = 1.1 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1.1)
    end)

    it("delay = 1.5 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1.5)
    end)

    it("delay = 1.9 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1.9)
    end)

    it("delay = 2 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 2)
    end)

    it("delay = 10 #fast", function ()
        helper(timer, tbl, TIMER_NAME, callback, 10)
    end)

    it("delay = 59 #slow_1", function ()
        helper(timer, tbl, TIMER_NAME, callback, 59)
    end)

    it("delay = 59.9 #slow_1", function ()
        helper(timer, tbl, TIMER_NAME, callback, 59.9)
    end)

    it("delay = 60 #slow_2", function ()
        helper(timer, tbl, TIMER_NAME, callback, 60)
    end)

    it("delay = 60.1 #slow_2", function ()
        helper(timer, tbl, TIMER_NAME, callback, 60.1)
    end)

    it("delay = 61 #slow_3", function ()
        helper(timer, tbl, TIMER_NAME, callback, 61)
    end)
end)