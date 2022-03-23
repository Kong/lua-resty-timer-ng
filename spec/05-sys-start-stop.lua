local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local TIMER_NAME_ONCE = "TEST-TIMER-ONCE"
local TIMER_NAME_EVERY = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2
local THREADS = 10


insulate("system start -> stop -> start #fast | ", function ()
    local timer
    local callback
    local tbl

    randomize()

    setup(function ()
        timer = require("resty.timer")
        timer:configure({ threads = THREADS })
        timer:start()

        tbl = {
            time = 0
        }

        callback = function (_, _tbl, ...)
            update_time()
            _tbl.time = now()
        end
    end)

    teardown(function ()
        timer:stop()
        timer:unconfigure()
        sleep(2)
        assert.same(1, timer_running_count())
    end)

    before_each(function ()
        update_time()
        tbl.time = 0
    end)

    it("once timer", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:once(TIMER_NAME_ONCE, callback, 1, tbl)
            assert.is_true(ok)
        end)

        timer:stop()
        sleep(1 + TOLERANCE)
        assert.same(0, tbl.time)

        update_time()
        timer:start()
        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)
    end)

    it("every create -> pause -> run -> cancel", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:every(TIMER_NAME_EVERY, callback, 1, tbl)
            assert.is_true(ok)
        end)

        timer:stop()
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:start(TIMER_NAME_EVERY)
        assert.is_true(ok)

        update_time()
        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        expected = expected + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        ok, _ = timer:cancel(TIMER_NAME_EVERY)
        assert.is_true(ok)

        tbl.time = 0
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

    end)

end)