local math_pow = math.pow
local math_floor = math.floor

local table_insert = table.insert

local ipairs = ipairs
local pcall = pcall
local pairs = pairs


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

    if not v then
        error(debug.traceback(message), 2)
    end
end


-- luacheck: push ignore
local assert = _M.assert
-- luacheck: pop


-- get average
function _M.get_avg(cur_value, cur_count, old_avg)
    -- recurrence formula
    return old_avg + ((cur_value - old_avg) / cur_count)
end


function _M.get_variance(cur_value, cur_count, old_variance, old_avg)
    -- recurrence formula
    return (((cur_count - 1)
        / math_pow(cur_count, 2)) * math_pow(cur_value - old_avg, 2))
        + (((cur_count - 1) / cur_count) * old_variance)
end


function _M.table_new(narray, nhash)
    return table_new(narray, nhash)
end


function _M.array_isempty(arr)
    return #arr == 0
end


function _M.array_merge(dst, src)
    assert(dst)

    if not src then
        return
    end

    for _, v in ipairs(src) do
        table_insert(dst, v)
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


function _M.convert_second_to_step(second, resolution)
    return math_floor(_M.round(second / resolution, 3))
end


function _M.print_queue(self)
    local pending_jobs = self.wheels.pending_jobs
    local ready_jobs = self.wheels.ready_jobs

    ngx.update_time()

    local str = "\n======== BEGIN PENDING ========" .. ngx.now() .. "\n"

    for _, v in ipairs(pending_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END PENDING ========\n"

    str = str .. "======== BEGIN READY ========\n"

    for _, v in ipairs(ready_jobs) do
        str = str .. tostring(v) .. "\n"
    end

    str = str .. "======== END READY ========"

    ngx.log(ngx.ERR, str)
end


function _M.print_wheel(wheels)
    ngx.update_time()

    local str = ""

    for level, wheel in ipairs(wheels.wheels) do
        str = str .. "\n======== BEGIN #" .. tostring(level)
            .. " ========" .. ngx.now() .. "\n"

        str = str .. "pointer = " .. wheel.pointer + 1 .. "\n"
        str = str .. "nelts = " .. wheel.nelts .. "\n"

        for i, v in ipairs(wheel.slots) do
            for _, value in ipairs(v) do
                str = str .. "index = " .. i .. ", " .. tostring(value) .. "\n"
            end
        end

        str = str .. "\n======== END #" .. tostring(level)
            .. " ========\n"
    end

    ngx.log(ngx.ERR, str)
end

function _M.round(value, digits)
    local x = 10 ^ digits
    return math_floor(value * x + 0.1) / x
end

return _M