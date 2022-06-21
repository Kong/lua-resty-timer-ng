local timer_module = require("resty.timerng")
local helper = require("helper")

local ngx_sleep = ngx.sleep

local MIN_THREADS = 16
local MAX_THREADS = 32
local AUTO_SCALING_INTERVAL = 1
local AUTO_SCALING_LOAD_THRESHOLD = 2

insulate("auto-scaling | ", function ()
    it("high load --> low load", function ()
        local timer = assert(timer_module.new({
            auto_scaling_interval = AUTO_SCALING_INTERVAL,
            auto_scaling_load_threshold = AUTO_SCALING_LOAD_THRESHOLD,
            min_threads = MIN_THREADS,
            max_threads = MAX_THREADS,
        }))

        assert(timer:start())

        -- create too many timers
        for _ = 1, MAX_THREADS * 4 do
            assert(timer:at(0, function ()
                ngx_sleep(AUTO_SCALING_INTERVAL * 2)
            end))
        end

        helper.wait_until(function ()
            local alive = timer:_debug_alive_worker_thread_count()
            assert.same(MAX_THREADS, alive)
        end, 5)


        helper.wait_until(function ()
            local alive = timer:_debug_alive_worker_thread_count()
            assert.same(MIN_THREADS, alive)
        end, 20)

    end)
end)