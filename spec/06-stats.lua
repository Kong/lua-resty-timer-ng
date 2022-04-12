local timer_module = require("resty.timer")

local sleep = ngx.sleep
local timer_running_count = ngx.timer.running_count

-- local TOLERANCE = 0.2
local THREADS = 32
local TOLERANCE = 0.2


insulate("stats |", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer_module.configure(timer, { threads = THREADS })
        timer_module.start(timer)
    end)

    lazy_teardown(function ()
        timer_module.freeze(timer)
        timer_module.unconfigure(timer)
        sleep(2)
        assert.same(1, timer_running_count())
    end)


    it("metadata #fast", function ()
        -- If this test fails,
        -- perhaps you need to update
        -- the function `job_create_meta`
        -- in the file `lib/resty/timer/job.lua`.

        local timer_name = "TEST"
        assert.is_truthy((timer:once(timer_name, function() end, 60)))

        local stats = timer_module.stats(timer)
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(timer_info)

        local callstack = timer_info.meta.callstack
        assert.same("spec/06-stats.lua", callstack[1].source)

        assert.is_true((timer:cancel(timer_name)))
    end)


    it("others #fast", function()
        local timer_name = "TEST"
        local record = 1
        local ok, _ = timer:every(timer_name, function ()
            if record < 3 then
                sleep(5)
                record = record + 1

            else
                sleep(5)
                error("expected error")
            end
        end, 1)

        assert.is_truthy(ok)

        for i = 1, 2 do
            sleep(1 + 5 + TOLERANCE)

            local stats = timer_module.stats(timer)
            local timer_info = stats.timers[timer_name]
            assert.is_truthy(timer_info)

            assert.near(5, timer_info.elapsed_time.avg, TOLERANCE)
            assert.near(5, timer_info.elapsed_time.max, TOLERANCE)
            assert.near(5, timer_info.elapsed_time.min, TOLERANCE)
            assert.same(i, timer_info.runs)
            assert.same(0, timer_info.faults)
            assert.same("", timer_info.last_err_msg)
        end

        sleep(1 + 5 + TOLERANCE)

        local stats = timer_module.stats(timer)
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(timer_info)

        assert.near(5, timer_info.elapsed_time.avg, TOLERANCE)
        assert.near(5, timer_info.elapsed_time.max, TOLERANCE)
        assert.near(5, timer_info.elapsed_time.min, TOLERANCE)
        assert.same(3, timer_info.runs)
        assert.same(1, timer_info.faults)
        assert.not_same("", timer_info.last_err_msg)

        assert.is_true((timer:cancel(timer_name)))
    end)

end)