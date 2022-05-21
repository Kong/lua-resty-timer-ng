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

        it("invalid `min_threads` and `max_threads`", function()
            assert.has.errors(function ()
                timer_module.new({
                    min_threads = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = -1,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = 1.5
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = -1,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    max_threads = 1.5,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = 10,
                    max_threads = 5,
                })
            end)
        end)


        it("invalid `auto_scaling_load_threshold`", function ()
            assert.has.errors(function ()
                timer_module.new({
                    auto_scaling_load_threshold = {},
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    auto_scaling_load_threshold = true,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    auto_scaling_load_threshold = "",
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    auto_scaling_load_threshold = -1,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    auto_scaling_load_threshold = 0,
                })
            end)

            assert.has.errors(function ()
                timer_module.new({
                    min_threads = 1.1,
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