local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count

local THREADS = 32

insulate("other bugs | ", function ()
    local timer

    randomize()

    lazy_setup(function ()
        timer = require("resty.timer")
        timer:configure({ threads = THREADS })
    end)

    lazy_teardown(function ()
        timer:stop()
        timer:unconfigure()
        sleep(2)
        assert.same(1, timer_running_count())
    end)

    before_each(function ()
        update_time()
    end)

    it("No.1 create a timer before the method `start()' is called #fast", function ()
        assert.has.errors(function()
            timer:once(nil, function() end, 10)
        end)
        assert.has.errors(function()
            timer:every(nil, function() end, 10)
        end)
    end)
end)


insulate("bugs of every timer | ", function ()
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

    before_each(function ()
        update_time()
    end)

    it("No.1 overlap #fast", function ()
        local flag = false
        local record = 0
        timer:every(nil, function (...)
            if now() - record < 0.3 then
                flag = true
            end
            record = now()
            sleep(1)
        end, 0.3)

        ngx.sleep((0.3 + 1) * 10)

        assert.is_false(flag)
    end)
end)