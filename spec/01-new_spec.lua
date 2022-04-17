local timer_module = require("resty.timer")

describe("new with | ", function ()
    it("empty options", function ()
        assert.has_no.errors(function ()
            timer_module.new()
            timer_module.new({})
        end)
    end)

    describe("invalid options | ", function ()
        it("not a table", function ()
            assert.has.errors(function ()
                timer_module.new(1)
            end)
        end)

        it("invalid `restart_thread_after_runs`", function ()
            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = -1,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    restart_thread_after_runs = 1.5,
                })
            end)
        end)

        it("invalid `threads", function()
            assert.has.errors(function ()
                timer_module.new({
                    threads = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    threads = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    threads = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    threads = -1
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    threads = 0
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    threads = 1.5
                })
            end)
        end)


        it("invalid `wheel_setting`", function ()
            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = {}
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = false
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = ""
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = -1
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 0
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 1.5
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { 1.5, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { -1, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { {}, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { "", 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { false, 1 }
                    },
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    wheel_setting = {
                        level = 2,
                        slots = { nil, 1 }
                    },
                })
            end)

        end) -- end it

    end) -- end the second describe

end) -- end the top describe