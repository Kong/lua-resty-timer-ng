
local timer_module = require("resty.timerng")
local helper = require("helper")

local sleep = ngx.sleep
local update_time = ngx.update_time
local now = ngx.now
local timer_running_count = ngx.timer.running_count
local string_format = string.format


local function callback_func(premature, create_time, delay)
    if premature then
        return
    end

    update_time()
    local now = now()
    local dict = ngx.shared["timer_jump_the_gun"]
    if not dict then
        error("not found shared dict: timer_jump_the_gun")
        return
    end

    dict:set("not_jump_the_gun", now - delay > create_time)
end


local function every_func()
    update_time()
end

local rand_intervals = {
    0.111,
    0.222,
    0.333,
    0.444,
    0.555,
    0.666,
    0.777,
    0.888,
    0.999,
}

for rand_interval in pairs(rand_intervals) do
    insulate("timer jump the gun", function ()
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
    
        after_each(function ()
            assert.has_no.errors(function ()
                timer:cancel(helper.TIMER_NAME_ONCE)
            end)
        end)
    
        it("test", function ()
            local delay = 30 * helper.RESOLUTION
            local interval = 10 * helper.RESOLUTION
            update_time()
    
            assert.has_no.errors(function ()
                assert(
                    timer:every(interval, every_func)
                )
            end)
    
            sleep(rand_interval)
    
            update_time()
            assert.has_no.errors(function ()
                local create_time = now()
                assert(
                    timer:named_at("foo", delay, callback_func, create_time, delay)
                )
            end)
    
            sleep(4)
    
            local dict = ngx.shared["timer_jump_the_gun"]
            if not dict then
                error("not found shared dict: timer_jump_the_gun")
                return
            end
    
            local jump_the_gun = dict:get("not_jump_the_gun")
            assert.is_not_nil(jump_the_gun)
            assert.is_true(jump_the_gun)
        end)
    end)
end

