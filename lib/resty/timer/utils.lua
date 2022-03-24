local pow = math.pow

local _M = {}


-- get average
function _M.get_avg(cur_value, cur_count, old_avg)
    -- recurrence formula
    return old_avg + ((cur_value - old_avg) / cur_count)
end


function _M.get_variance(cur_value, cur_count, old_variance, old_avg)
    -- recurrence formula
    return (((cur_count - 1) / pow(cur_count, 2)) * pow(cur_value - old_avg, 2))
        + (((cur_count - 1) / cur_count) * old_variance)
end


function _M.is_empty_table(t)
    if not t then
        return true
    end

    -- luacheck: ignore
    for k, v in pairs(t) do
        return false
    end

    return true
end


function _M.get_a_item_from_table(tbl)
    if not tbl then
        return nil
    end

    -- luacheck: ignore
    for k, v in pairs(tbl) do
        return v
    end

    return nil
end


function _M.float_compare(left, right)
    local delta = left - right
    if delta < -0.01 then
        return -1

    elseif delta > 0.01 then
        return 1

    else
        return 0
    end
end

-- local function print_queue(self)
--     local pending_jobs = self.wheels.pending_jobs
--     local ready_jobs = self.wheels.ready_jobs

--     update_time()

--     local str = "\n======== BEGIN PENDING ========" .. now() .. "\n"

--     for _, v in pairs(pending_jobs) do
--         str = str .. tostring(v) .. "\n"
--     end

--     str = str .. "======== END PENDING ========\n"

--     str = str .. "======== BEGIN READY ========"
--        .. tostring(self.semaphore_mover:count()) .. "\n"

--     for _, v in pairs(ready_jobs) do
--         str = str .. tostring(v) .. "\n"
--     end

--     str = str .. "======== END READY ========"

--     log(ERR, str)
-- end


-- function _M:print_wheel(wheels)
--     local wheel

--     ngx.update_time()

--     local str = "\n======== BEGIN MSEC ========" .. ngx.now() .. "\n"
--     wheel = wheels.msec
--     str = str .. "pointer = " .. wheel.pointer .. "\n"
--     str = str .. "nelt = " .. wheel.nelt .. "\n"
--     for i, v in ipairs(wheel.array) do
--         for _, value in pairs(v) do
--             str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
--         end
--     end
--     str = str .. "========= END MSEC =========\n"


--     str = str .. "\n======== BEGIN SECOND ========\n"
--     wheel = wheels.sec
--     str = str .. "pointer = " .. wheel.pointer .. "\n"
--     str = str .. "nelt = " .. wheel.nelt .. "\n"
--     for i, v in ipairs(wheel.array) do
--         for _, value in pairs(v) do
--             str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
--         end
--     end
--     str = str .. "========= END SECOND ========="


    -- str = str .. "\n======== BEGIN MINUTE ========\n"
    -- wheel = wheels.min
    -- str = str .. "pointer = " .. wheel.pointer .. "\n"
    -- str = str .. "nelt = " .. wheel.nelt .. "\n"
    -- for i, v in ipairs(wheel.array) do
    --     for _, value in pairs(v) do
    --         str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
    --     end
    -- end
    -- str = str .. "========= END MINUTE ========="


    -- str = str .. "\n======== BEGIN HOUR ========\n"
    -- wheel = wheels.hour
    -- str = str .. "pointer = " .. wheel.pointer .. "\n"
    -- str = str .. "nelt = " .. wheel.nelt .. "\n"
    -- for i, v in ipairs(wheel.array) do
    --     for _, value in pairs(v) do
    --         str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
    --     end
    -- end
    -- str = str .. "========= END HOUR ========="

--     ngx.log(ngx.ERR, str)
-- end


-- local function round(value, digits)
--     local x = 10 * digits
--     return floor(value * x + 0.5) / x
-- end

return _M