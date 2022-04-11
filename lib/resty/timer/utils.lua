local pow = math.pow
local floor = math.floor
local pcall = pcall

local std_assert = assert
local pairs = pairs

local ngx = ngx

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local table_isempty

do
    local has_table_isempty, _table_isempty = pcall(require, "table.isempty")

    if has_table_isempty then
        table_isempty = _table_isempty

    else
        table_isempty = function(tbl)
            -- luacheck: ignore
            for _, _ in pairs(tbl) do
                return false
            end

            return true
        end
    end
end


local table_new

do
    local has_table_new, _table_new = pcall(require, "table.new")

    if has_table_new then
        table_new = _table_new

    else
        table_new = function ()
            return { }
        end
    end
end


local table_deepcopy

do
    local has_penlight_tablex, pl_tablex = pcall(require, "pl.tablex")
    if has_penlight_tablex then
        table_deepcopy = pl_tablex.deepcopy

    else
        table_deepcopy = function(tbl)
            local ret = {}

            for k, v in pairs(tbl) do
                if type(v) ~= "table" then
                    ret[k] = v

                else
                    ret[k] = table_deepcopy(v)
                end
            end

            return ret
        end
    end
end



local _M = {}


function _M.assert(v, message)
    if message == nil then
        message = "assertion failed!"
    end

    std_assert(v, debug.traceback(message))
end


local assert = _M.assert


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


function _M.table_new(narray, nhash)
    return table_new(narray, nhash)
end


function _M.table_is_empty(tbl)
    if not tbl then
        return true
    end

    return table_isempty(tbl)
end


function _M.table_get_a_item(tbl)
    if not tbl then
        return nil
    end

    -- luacheck: ignore
    for _, v in pairs(tbl) do
        return v
    end

    return nil
end


function _M.table_append(dst, src)
    assert(dst and src)

    for k, v in pairs(src) do
        assert(not dst[k])
        dst[k] = v
    end
end


function _M.table_deepcopy(tbl)
    return table_deepcopy(tbl)
end


function _M.float_compare(left, right)
    local delta = left - right
    if delta < -0.01 then
        return -1
    end

    if delta > 0.01 then
        return 1
    end

    return 0
end

function _M.print_queue(self)
    local pending_jobs = self.wheels.pending_jobs
    local ready_jobs = self.wheels.ready_jobs

    ngx.update_time()

    local str = "\n======== BEGIN PENDING ========" .. ngx.now() .. "\n"

    for _, v in pairs(pending_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END PENDING ========\n"

    str = str .. "======== BEGIN READY ========"
       .. tostring(self.semaphore_mover:count()) .. "\n"

    for _, v in pairs(ready_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END READY ========"

    ngx.log(ngx.ERR, str)
end


function _M.print_wheel(wheels)
    local wheel

    ngx.update_time()

    local str = "\n======== BEGIN MSEC ========" .. ngx.now() .. "\n"
    wheel = wheels.msec_wheel
    str = str .. "pointer = " .. wheel.pointer + 1 .. "\n"
    str = str .. "nelts = " .. wheel.nelts .. "\n"
    for i, v in ipairs(wheel.slots) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END MSEC ========="


    str = str .. "\n======== BEGIN SECOND ========\n"
    wheel = wheels.second_wheel
    str = str .. "pointer = " .. wheel.pointer + 1 .. "\n"
    str = str .. "nelts = " .. wheel.nelts .. "\n"
    for i, v in ipairs(wheel.slots) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END SECOND ========="


    str = str .. "\n======== BEGIN MINUTE ========\n"
    wheel = wheels.minute_wheel
    str = str .. "pointer = " .. wheel.pointer + 1 .. "\n"
    str = str .. "nelts = " .. wheel.nelts .. "\n"
    for i, v in ipairs(wheel.slots) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END MINUTE ========="


    str = str .. "\n======== BEGIN HOUR ========\n"
    wheel = wheels.hour_wheel
    str = str .. "pointer = " .. wheel.pointer + 1 .. "\n"
    str = str .. "nelts = " .. wheel.nelts .. "\n"
    for i, v in ipairs(wheel.slots) do
        for _, value in pairs(v) do
            str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
        end
    end
    str = str .. "========= END HOUR ========="

    ngx.log(ngx.ERR, str)
end


function _M:round(value, digits)
    local x = 10 * digits
    return floor(value * x + 0.5) / x
end

return _M