local sleep = ngx.sleep
local log = ngx.log
local ERR = ngx.ERR
local update_time = ngx.update_time
local now = ngx.now

local TIMER_NAME_ONCE = "TEST-TIMER-ONCE"
local TIMER_NAME_EVERY = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2


insulate("timer #fast | ", function ()
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

    it("once create -> pause -> run", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:once(TIMER_NAME_ONCE, callback, 1, tbl)
            assert.is_true(ok)
        end)

        timer:pause(TIMER_NAME_ONCE)
        sleep(1 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:run(TIMER_NAME_ONCE)
        assert.is_true(ok)

        update_time()
        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)
    end)

    it("once create -> cancel", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:once(TIMER_NAME_ONCE, callback, 1, tbl)
            assert.is_true(ok)
        end)

        timer:cancel(TIMER_NAME_ONCE)
        sleep(1 + TOLERANCE)
        assert.same(0, tbl.time)
    end)

    it("every create -> pause -> run -> cancel", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:every(TIMER_NAME_EVERY, callback, 1, tbl)
            assert.is_true(ok)
        end)

        timer:pause(TIMER_NAME_EVERY)
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:run(TIMER_NAME_EVERY)
        assert.is_true(ok)

        update_time()
        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        local expected = expected + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)

        ok, _ = timer:cancel(TIMER_NAME_EVERY)

        tbl.time = 0
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

    end)

end)