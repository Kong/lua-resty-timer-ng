local timer_module = require("resty.timer")
local helper = require("helper")

local sleep = ngx.sleep
local timer_running_count = ngx.timer.running_count

local TOLERANCE = 0.2


insulate("stats |", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new()
        local ok, _ = timer:start()
        assert.is_true(ok)
    end)

    lazy_teardown(function ()
        timer:freeze()
        timer:destroy()

        helper.wait_until(function ()
            assert.same(1, timer_running_count())
            return true
        end)

    end)


    it("metadata", function ()
        -- If this test fails,
        -- perhaps you need to update
        -- the function `job_create_meta`
        -- in the file `lib/resty/timer/job.lua`.

        local timer_name = "TEST"
        assert.is_truthy((timer:once(timer_name, 60, function() end)))

        local stats = timer:stats(true)
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(timer_info)

        local callstack = timer_info.meta.callstack
        assert.same("spec/06-stats_spec.lua", callstack[1].source)

        assert.is_true((timer:cancel(timer_name)))
    end)

    it("no verbose", function ()
        local stats = timer:stats(false)
        assert(stats.timers == nil)

        stats = timer:stats()
        assert(stats.timers == nil)
    end)


    it("others", function()
        local timer_name = "TEST"
        local record = 1
        local ok, _ = timer:every(timer_name, 1, function ()
            if record < 3 then
                sleep(5)
                record = record + 1

            else
                sleep(5)
                error("expected error")
            end
        end)

        assert.is_truthy(ok)

        ok, _ = timer:every(nil, 99999, function () end)

        assert.is_truthy(ok)

        for i = 1, 2 do
            sleep(1 + 5 + TOLERANCE)

            local stats = timer:stats(true)
            local stats_sys = stats.sys
            local timer_info = stats.timers[timer_name]
            assert.is_truthy(stats_sys)
            assert.is_truthy(timer_info)

            assert.same(1, stats_sys.waiting)
            assert.near(5, timer_info.elapsed_time.avg, TOLERANCE)
            assert.near(5, timer_info.elapsed_time.max, TOLERANCE)
            assert.near(5, timer_info.elapsed_time.min, TOLERANCE)
            assert.same(i, timer_info.runs)
            assert.same(0, timer_info.faults)
            assert.same("", timer_info.last_err_msg)
        end

        sleep(1 + 5 + TOLERANCE)

        local stats = timer:stats(true)
        local stats_sys = stats.sys
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(stats_sys)
        assert.is_truthy(timer_info)

        assert.same(1, stats_sys.waiting)
        assert.near(5, timer_info.elapsed_time.avg, TOLERANCE)
        assert.near(5, timer_info.elapsed_time.max, TOLERANCE)
        assert.near(5, timer_info.elapsed_time.min, TOLERANCE)
        assert.same(3, timer_info.runs)
        assert.same(1, timer_info.faults)
        assert.not_same("", timer_info.last_err_msg)

        assert.is_true((timer:cancel(timer_name)))
    end)

end)