local timer_module = require("resty.timerng")
local helper = require("helper")

local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count


insulate("other bugs | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })
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
    end)

    it("No.1 create a timer before the method `start()' is called", function ()
        assert.has.errors(function()
            timer:named_at(nil, 10, function() end)
        end)
        assert.has.errors(function()
            timer:named_every(nil, 10, function() end)
        end)
    end)
end)


insulate("bugs of every timer | ", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 16,
            max_threads = 32,
        })

        assert(timer:start())
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
    end)

    it("No.1 overlap", function ()
        local flag = false
        local record = 0
        assert(timer:named_every(nil, 0.3, function (...)
            if now() - record < 0.3 then
                flag = true
            end
            record = now()
            sleep(1)
        end))

        ngx.sleep((0.3 + 1) * 10)

        assert.is_false(flag)
    end)
end)

insulate("should not share ngx.ctx across different timers", function ()
    local timer = { }

    randomize()

    lazy_setup(function ()
        timer = timer_module.new({
            min_threads = 1,
            max_threads = 2,
        })

        assert(timer:start())
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
    end)

    it("", function ()
        local flag = false
        assert(timer:at(0, function ()
            ngx.update_time()
            ngx.sleep(0.5) -- wait for 0.5 seconds to exhaust the thread pool
            ngx.ctx.a = 1
            flag = true
        end))

        assert(timer:at(0, function ()
            ngx.update_time()
            ngx.sleep(0.5) -- wait for 0.5 seconds to exhaust the thread pool
            ngx.ctx.a = 1
            flag = true
        end))

        ngx.update_time()
        ngx.sleep(1)

        assert.is_true(flag)

        assert(timer:at(0, function ()
            ngx.sleep(0.5)
            assert.is_nil(ngx.ctx.a)
        end))

        assert(timer:at(0, function ()
            ngx.sleep(0.5)
            assert.is_nil(ngx.ctx.a)
        end))
    end)
end)