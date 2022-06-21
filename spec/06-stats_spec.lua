local timer_module = require("resty.timerng")
local helper = require("helper")

local sleep = ngx.sleep
local timer_running_count = ngx.timer.running_count

local TOLERANCE = 0.2


insulate("stats | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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

        timer:set_debug(false)
        local timer_name = assert(timer:at(60, function() end))
        local stats = timer:stats({
            verbose = true,
        })
        local timer_info = assert(stats.timers[timer_name])
        assert(timer_info.meta == nil)
        assert(timer:cancel(timer_name))


        timer:set_debug(true)
        timer_name = assert(timer:at(60, function() end))
        stats = timer:stats({
            verbose = true,
        })
        timer_info = assert(stats.timers[timer_name])
        local callstack = timer_info.meta.callstack
        local meta_name = timer_info.meta.name

        if not string.find(meta_name, "create()", 1, true) then
            error("incorrect meta name: " .. meta_name)
        end

        if not string.find(callstack, "spec/06-stats_spec.lua", 1, true) then
            error("incorrect callstack: \n" .. callstack)
        end

        assert(timer:cancel(timer_name))
        timer:set_debug(false)
    end)
end)


insulate("stats | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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

    it("no verbose", function ()
        local stats = timer:stats()
        assert(stats.timers == nil)

        stats = timer:stats({
            verbose = false,
        })
        assert(stats.timers == nil)
    end)
end)


insulate("stats | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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

    it("flamegraph", function ()
        timer:set_debug(true)

        assert(timer:named_at(nil, 0, function ()
            ngx.sleep(1)
        end))

        assert(timer:named_at(nil, 0, function ()
            ngx.sleep(2)
        end))

        assert(timer:named_at(nil, 0, function ()
            ngx.sleep(3)
        end))

        assert(timer:named_at(nil, 0, function ()
            ngx.sleep(4)
        end))

        assert(timer:named_at(nil, 0, function ()
            ngx.sleep(5)
        end))

        local stats = timer:stats({
            verbose = true,
            flamegraph = true,
        })

        assert(stats)
        assert(stats.timers)
        assert(stats.flamegraph)
        assert(stats.flamegraph.running)
        assert(stats.flamegraph.pending)

        print("flamegraph.running\n", stats.flamegraph.running)
        print("flamegraph.pending\n", stats.flamegraph.pending)
        print("flamegraph.elapsed_time\n", stats.flamegraph.elapsed_time)
        print("============================")

        ngx.sleep(0.2)

        stats = timer:stats({
            verbose = true,
            flamegraph = true,
        })

        assert(stats)
        assert(stats.timers)
        assert(stats.flamegraph)
        assert(stats.flamegraph.running)
        assert(stats.flamegraph.pending)

        print("flamegraph.running\n", stats.flamegraph.running)
        print("flamegraph.pending\n", stats.flamegraph.pending)
        print("flamegraph.elapsed_time\n", stats.flamegraph.elapsed_time)
        print("============================")

        ngx.sleep(7)

        stats = timer:stats({
            verbose = true,
            flamegraph = true,
        })

        assert(stats)
        assert(stats.timers)
        assert(stats.flamegraph)
        assert(stats.flamegraph.running)
        assert(stats.flamegraph.pending)

        print("flamegraph.running\n", stats.flamegraph.running)
        print("flamegraph.pending\n", stats.flamegraph.pending)
        print("flamegraph.elapsed_time\n", stats.flamegraph.elapsed_time)
        print("============================")

        timer:set_debug(false)
    end)
end)


insulate("stats | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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

    it("others", function()
        timer:set_debug(true)
        local timer_name = "TEST"
        local record = 1
        assert(timer:named_every(timer_name, 1, function ()
            if record < 3 then
                sleep(5)
                record = record + 1

            else
                sleep(5)
                error("expected error")
            end
        end))

        assert(timer:named_every(nil, 99999, function () end))

        for i = 1, 2 do
            sleep(1 + 5 + TOLERANCE)

            local stats = timer:stats({
                verbose = true,
            })
            local stats_sys = stats.sys
            local timer_info = stats.timers[timer_name]
            assert.is_truthy(stats_sys)
            assert.is_truthy(timer_info)

            assert.same(1, stats_sys.waiting)
            assert.near(5, timer_info.stats.elapsed_time.avg, TOLERANCE)
            assert.near(5, timer_info.stats.elapsed_time.max, TOLERANCE)
            assert.near(5, timer_info.stats.elapsed_time.min, TOLERANCE)
            assert.same(i, timer_info.stats.runs)
            assert.same(i, timer_info.stats.finish)
            assert.same("", timer_info.stats.last_err_msg)
        end

        sleep(1 + 5 + TOLERANCE)

        local stats = timer:stats({
            verbose = true,
        })
        local stats_sys = stats.sys
        local timer_info = stats.timers[timer_name]
        assert.is_truthy(stats_sys)
        assert.is_truthy(timer_info)

        assert.same(1, stats_sys.waiting)
        assert.near(5, timer_info.stats.elapsed_time.avg, TOLERANCE)
        assert.near(5, timer_info.stats.elapsed_time.max, TOLERANCE)
        assert.near(5, timer_info.stats.elapsed_time.min, TOLERANCE)
        assert.same(3, timer_info.stats.runs)
        assert.same(2, timer_info.stats.finish)
        assert.not_same("", timer_info.last_err_msg)

        assert.is_true((timer:cancel(timer_name)))
    end)

end)