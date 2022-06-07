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

    before_each(function ()
        update_time()
    end)

    it("No.1 overlap", function ()
        local flag = false
        local record = 0
        timer:named_every(nil, 0.3, function (...)
            if now() - record < 0.3 then
                flag = true
            end
            record = now()
            sleep(1)
        end)

        ngx.sleep((0.3 + 1) * 10)

        assert.is_false(flag)
    end)
end)