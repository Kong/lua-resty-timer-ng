local math_pow = math.pow
local math_floor = math.floor

local type = type
local pcall = pcall
local pairs = pairs


local table_new = require "table.new"
local table_clear = require "table.clear"


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


_M.table_new = table_new
_M.table_clear = table_clear
_M.table_deepcopy = table_deepcopy


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


function _M.round(value, digits)
    local x = 10 ^ digits
    return math_floor(value * x + 0.1) / x
end


return _M
