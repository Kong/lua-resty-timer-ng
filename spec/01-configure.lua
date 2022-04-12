local timer_module = require("resty.timer")

insulate("configure without options #fast", function()
    local timer = { }
    it("", function()
        local ok, _ = timer_module.configure(timer)
        assert.is_true(ok)
    end)
end)


insulate("configure with empty options #fast", function()
    local timer = { }
    it("", function ()
        local ok, _ = timer_module.configure(timer, {})
        assert.is_true(ok)
    end)
end)


insulate("configure with invalid options #fast | ", function ()
    insulate("not a table", function ()
        local timer = { }
        it("", function ()
            assert.has.errors(function ()
                timer_module.configure(timer, 1)
            end)
        end)
    end)


    insulate("invalid `restart_thread_after_runs` | ", function ()
        insulate("not a number", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        restart_thread_after_runs = ""
                    })
                end)
            end)
        end)

        insulate("not greater than 0", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        restart_thread_after_runs = -1
                    })
                end)

                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        restart_thread_after_runs = 0
                    })
                end)
            end)
        end)

        insulate("not an integer", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        restart_thread_after_runs = 0.1
                    })
                end)
            end)
        end)
    end)


    insulate("invalid `threads` | ", function ()
        insulate("not a number", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        threads = ""
                    })
                end)
            end)
        end)

        insulate("not greater than 0", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        threads = -1
                    })
                end)

                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        threads = 0
                    })
                end)
            end)
        end)

        insulate("not an integer", function ()
            local timer = { }
            it("", function ()
                assert.has.errors(function ()
                    timer_module.configure(timer, {
                        threads = 0.1
                    })
                end)
            end)
        end)
    end)
end)