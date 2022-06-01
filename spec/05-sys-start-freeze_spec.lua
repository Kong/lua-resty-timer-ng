local helper = require("helper")

local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local TIMER_NAME_ONCE = "TEST-TIMER-ONCE"
local TIMER_NAME_EVERY = "TEST-TIMER-EVERY"
local TOLERANCE = 0.2


insulate("system start -> freeze -> start | ", function ()
    local timer_module = require("resty.timer")
    local timer = { }
    local callback
    local tbl

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
        local ok, _ = timer:start()
        assert.is_true(ok)

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

    it("once timer", function ()
        assert.has_no.errors(function ()
            local ok, _ = timer:once(TIMER_NAME_ONCE, 1, callback, tbl)
            assert.is_truthy(ok)
        end)

        timer:freeze()
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
            local ok, _ = timer:every(TIMER_NAME_EVERY, 1, callback, tbl)
            assert.is_truthy(ok)
        end)

        timer_module.freeze(timer)
        sleep(2 + TOLERANCE)
        assert.same(0, tbl.time)

        local ok, _ = timer:start()
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


insulate("worker exiting | ", function ()
    local worker_exiting_flag = false
    local native_ngx_worker_exiting = ngx.worker.exiting

    local function ngx_worker_exiting_patched()
        return worker_exiting_flag
    end

    local timer_module

    lazy_setup(function ()
        -- luacheck: push ignore
        ngx.worker.exiting = function ()
            return ngx_worker_exiting_patched()
        end
        -- luacheck: pop

        timer_module = require("resty.timer")
    end)

    lazy_teardown(function ()
        -- luacheck: push ignore
        ngx.worker.exiting = native_ngx_worker_exiting
        -- luacheck: pop
    end)

    after_each(function ()
        worker_exiting_flag = false
    end)

    it("flush all timers", function ()
        local timers = 10
        local counter = 0
        local timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })

        assert(timer:start())

        for _ = 1, timers / 2 do
            assert(timer:once(nil, 120, function (premature)
                if premature then
                    counter = counter + 1
                end
            end))

            assert(timer:every(nil, 120, function (premature)
                if premature then
                    counter = counter + 1
                end
            end))
        end

        worker_exiting_flag = true

        ngx.update_time()

        -- waiting for worker timer was woke-up
        ngx.sleep(2)

        assert.same(counter, timers)
    end)
end)