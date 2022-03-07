

insulate("configure without options", function()
    local timer = require("resty.timer")
    it("", function() 
        local ok, _ = timer:configure()
        assert.is_true(ok)
    end)
end)


insulate("configure with empty options", function()
    local timer = require("resty.timer")
    it("", function ()
        local ok, _ = timer:configure({})
        assert.is_true(ok)
    end)
end)


insulate("configure with invalid options | ", function ()
    insulate("not a table", function ()
        local timer = require("resty.timer")
        it("", function ()
            assert.has.errors(function ()
                timer:configure(1)
            end)
        end)
    end)


    insulate("invalid `recreate_interval` | ", function ()
        insulate("not a number", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        recreate_interval = ""
                    })
                end)
            end)
        end)

        insulate("not greater than 0", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        recreate_interval = -1
                    })
                end)

                assert.has.errors(function ()
                    timer:configure({
                        recreate_interval = 0
                    })
                end)
            end)
        end)

        insulate("not an integer", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        recreate_interval = 0.1
                    })
                end)
            end)
        end)
    end)


    insulate("invalid `threads` | ", function ()
        insulate("not a number", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        threads = ""
                    })
                end)
            end)
        end)

        insulate("not greater than 0", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        threads = -1
                    })
                end)

                assert.has.errors(function ()
                    timer:configure({
                        threads = 0
                    })
                end)
            end)
        end)

        insulate("not an integer", function ()
            local timer = require("resty.timer")
            it("", function ()
                assert.has.errors(function ()
                    timer:configure({
                        threads = 0.1
                    })
                end)
            end)
        end)
    end)
end)