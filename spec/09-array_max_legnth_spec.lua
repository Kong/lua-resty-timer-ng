local timer_module = require("resty.timerng")
local array_module = require("resty.timerng.array")


describe("array max_length limit", function()
    it("push_right > max_length", function()
        local arr = array_module.new(2, 3)
        assert.is_nil(arr:push_right(1))
        assert.is_nil(arr:push_right(2))
        assert.is_nil(arr:push_right(3))
        local err = arr:push_right(4)
        assert.same("list is full", err)
    end)

    it("push_left > max_length", function()
        local arr = array_module.new(2, 2)
        assert.is_nil(arr:push_left(1))
        assert.is_nil(arr:push_left(2))
        local err = arr:push_left(3)
        assert.same("list is full", err)
    end)
end)


describe("max_pending_jobs limit", function()
    it("pending_jobs == 3", function()
        local max_pending = 3
        local timer = assert(timer_module.new({
            max_pending_jobs = max_pending,
            min_threads = 1,
            max_threads = 2,
        }))
        assert(timer:start())

        for i = 1, max_pending do
            assert.has_no.errors(function()
                assert(timer:at(0, function() end))
            end)
        end

        local ok, err = timer:at(0, function() end)
        assert.is_false(ok)
        assert.matches("failed to push job to pending jobs: list is full", err)
    end)

    it("pending_jobs == 0", function()
        local max_pending = 3
        local timer = assert(timer_module.new({
            min_threads = 1,
            max_threads = 2,
        }))
        assert(timer:start())

        for i = 1, max_pending do
            assert.has_no.errors(function()
                assert(timer:at(0, function() end))
            end)
        end

        local ok, err = timer:at(0, function() end)
        print("ok, err = ", ok, err)
        assert.is_not_false(ok)
        assert.is_nil(err)
    end)
end)