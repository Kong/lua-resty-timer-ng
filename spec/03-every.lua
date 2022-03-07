local sleep = ngx.sleep
local log = ngx.log
local ERR = ngx.ERR
local update_time = ngx.update_time
local now = ngx.now

local TIMER_NAME = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2

local function helper(t, tbl, name, callback, interval)
    assert.has_no.errors(function ()
        local ok, _ = t:every(name, callback, interval, tbl)
        assert.is_true(ok)
    end)

    local expected = now() + interval
    sleep(interval + TOLERANCE)
    assert.near(expected, tbl.time, TOLERANCE)

    tbl.time = 0

    expected = expected + interval
    sleep(interval + TOLERANCE)
    assert.near(expected, tbl.time, TOLERANCE)
end


insulate("create a every timer with invalid arguments | ", function ()
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


insulate("create a every timer | ", function ()
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
        local ok, _ = timer:cancel(TIMER_NAME)
        assert.is_true(ok)
    end)

    it("interval = 0.1", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:every(TIMER_NAME, callback, 0.1, tbl)
            assert.is_true(ok)
        end)
    
        local expected = now() + 2 * 0.1
        sleep(2 * 0.1 + TOLERANCE)
        assert.is_true(tbl.time > expected)
        
    end)

    it("interval = 0.5", function ()
        helper(timer, tbl, TIMER_NAME, callback, 0.5)
    end)

    it("interval = 0.9", function ()
        helper(timer, tbl, TIMER_NAME, callback, 0.9)
    end)

    it("interval = 1", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1)
    end)

    it("interval = 1.1", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1)
    end)

    it("interval = 1.5", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1.5)
    end)

    it("interval = 1.9", function ()
        helper(timer, tbl, TIMER_NAME, callback, 1.9)
    end)

    it("interval = 2", function ()
        helper(timer, tbl, TIMER_NAME, callback, 2)
    end)

    it("interval = 10", function ()
        helper(timer, tbl, TIMER_NAME, callback, 10)
    end)

    it("interval = 59", function ()
        helper(timer, tbl, TIMER_NAME, callback, 59)
    end)

    it("interval = 59.9", function ()
        helper(timer, tbl, TIMER_NAME, callback, 59.9)
    end)

    it("interval = 60", function ()
        helper(timer, tbl, TIMER_NAME, callback, 60)
    end)

    it("interval = 60.1", function ()
        helper(timer, tbl, TIMER_NAME, callback, 60.1)
    end)

    it("interval = 61", function ()
        helper(timer, tbl, TIMER_NAME, callback, 61)
    end)
end)


insulate("create a every timer | ", function ()
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
            sleep(3)
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
        local ok, _ = timer:cancel(TIMER_NAME)
        assert.is_true(ok)
    end)

    it("overlap", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:every(TIMER_NAME, callback, 1, tbl)
            assert.is_true(ok)
        end)

        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        sleep(3)
        expected = expected + 4
        assert.near(expected, tbl.time, TOLERANCE)

    end)


end)