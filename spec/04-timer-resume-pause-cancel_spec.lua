local timer_module = require("resty.timerng")
local helper = require("helper")

local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local TIMER_NAME_ONCE = "TEST-TIMER-ONCE"
local TIMER_NAME_EVERY = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2


insulate("timer | ", function ()
    local timer = { }
    local callback
    local tbl

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })

        assert(timer:start())

        tbl = {
            time = 0
        }

        callback = function (_, _tbl, ...)
            update_time()
            _tbl.time = now()
        end
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

    it("once create -> pause -> resume", function ()
        assert.has_no.errors(function ()
            assert(timer:named_at(TIMER_NAME_ONCE, 1, callback, tbl))
        end)

        timer:pause(TIMER_NAME_ONCE)
        sleep(1 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:resume(TIMER_NAME_ONCE)
        assert.is_true(ok)

        update_time()
        local expected = now() + 1
        sleep(1 + TOLERANCE)
        assert.near(expected, tbl.time, TOLERANCE)
    end)

    it("once create -> cancel", function ()
        assert.has_no.errors(function ()
            assert(timer:named_at(TIMER_NAME_ONCE, 1, callback, tbl))
        end)

        timer:cancel(TIMER_NAME_ONCE)
        sleep(1 + TOLERANCE)
        assert.same(0, tbl.time)
    end)

    it("every create -> pause -> resume -> cancel", function ()
        assert.has_no.errors(function ()
            assert(timer:named_every(TIMER_NAME_EVERY, 1, callback, tbl))
        end)

        timer:pause(TIMER_NAME_EVERY)
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:resume(TIMER_NAME_EVERY)
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