local sleep = ngx.sleep
local timer_running_count = ngx.timer.running_count

-- local TOLERANCE = 0.2
local THREADS = 32
local TOLERANCE = 0.2


insulate("stats |", function ()
    local timer

    randomize()

    lazy_setup(function ()
        timer = require("resty.timer")
        timer:configure({ threads = THREADS })
        timer:start()
    end)

    lazy_teardown(function ()
        timer:stop()
        timer:unconfigure()
        sleep(2)
        assert.same(1, timer_running_count())
    end)


    it("metadata #fast", function ()
        -- If this test fails,
        -- perhaps you need to update
        -- the function `job_create_meta`
        -- in the file `lib/resty/timer/job.lua`.

        local timer_name = "TEST"
        assert.is_true((timer:once(timer_name, function() end, 60)))

        local stats = timer:stats()
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(timer_info)

        local callstack = timer_info.meta.callstack
        assert.same("spec/06-stats.lua", callstack[1].source)

        assert.is_true((timer:cancel(timer_name)))
    end)


    it("others #fast", function()
        local timer_name = "TEST"
        local record = 1
        timer:every(timer_name, function ()
            if record < 3 then
                sleep(5)
                record = record + 1

            else
                sleep(5)
                error("expected error")
            end
        end, 1)

        for i = 1, 2 do
            sleep(1 + 5 + TOLERANCE)

            local stats = timer:stats()
            local timer_info = stats.timers[timer_name]
            assert.is_truthy(timer_info)

            assert.near(5, timer_info.runtime.avg, TOLERANCE)
            assert.near(5, timer_info.runtime.max, TOLERANCE)
            assert.near(5, timer_info.runtime.min, TOLERANCE)
            assert.same(i, timer_info.runs)
            assert.same(0, timer_info.faults)
            assert.same("", timer_info.last_err_msg)
        end

        sleep(1 + 5 + TOLERANCE)

        local stats = timer:stats()
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(timer_info)

        assert.near(5, timer_info.runtime.avg, TOLERANCE)
        assert.near(5, timer_info.runtime.max, TOLERANCE)
        assert.near(5, timer_info.runtime.min, TOLERANCE)
        assert.same(3, timer_info.runs)
        assert.same(1, timer_info.faults)
        assert.same("spec/06-stats.lua:60: expected error", timer_info.last_err_msg)

        assert.is_true((timer:cancel(timer_name)))
    end)

end)