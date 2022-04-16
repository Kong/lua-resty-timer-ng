local timer_module = require("resty.timer")

describe("configure with #fast | ", function ()
    it("empty options", function ()
        local ok, _ = timer_module.configure({})
        assert.is_true(ok)

        ok, _ = timer_module.configure({}, {})
        assert.is_true(ok)
    end)

    it("nil first argument ", function ()
        assert.has.errors(function ()
            timer_module.configure(nil, {})
        end)
    end)

    describe("invalid options | ", function ()
        it("not a table", function ()
            assert.has.errors(function ()
                timer_module.configure({}, 1)
            end)
        end)

        it("invalid `restart_thread_after_runs`", function ()
            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = -1,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    restart_thread_after_runs = 1.5,
                })
            end)
        end)

        it("invalid `threads", function()
            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = -1
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = 0
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    threads = 1.5
                })
            end)
        end)


        it("invalid `wheel_setting`", function ()
            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = {}
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = false
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = ""
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = -1
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 0
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 1.5
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { 1.5, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { -1, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { {}, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { "", 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { false, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.configure({}, {
                    wheel_setting = {
                        level = 2,
                        slots = { nil, 1 }
                    },
                })
            end)

        end) -- end it

    end) -- end the second describe

end) -- end the top describe