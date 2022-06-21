local math_pow = math.pow
local math_floor = math.floor

local debug_getinfo = debug.getinfo

local table_insert = table.insert
local table_concat = table.concat
local table_remove = table.remove

local string_sub = string.sub
local string_len = string.len
local string_format = string.format

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


function _M.table_clear(tbl)
    table_clear(tbl)
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


function _M.round(value, digits)
    local x = 10 ^ digits
    return math_floor(value * x + 0.1) / x
end


---catch the fold callstack for flamegraph
---@param max_depth? number optional, max depth of callstack (default = 512)
---@return string top_frame like "@/timer.lua:64:dns_timer()"
---@return string fold_callstack
---like "@/timer.lua:32:init();@/timer.lua:64:dns_timer()"
---@warning bad performance
function _M.catch_fold_callstack(max_depth)
    if not max_depth then
        max_depth = 512
    end

    local base_callstack_level = 1

    local callstack = {}

    for i = 1, max_depth do
        local info = debug_getinfo(i + base_callstack_level, "nSl")

        if not info or info.short_src == "[C]" then
            break
        end

        local str = string_format("%s:%d:%s();",
                                  info.source,
                                  info.currentline,
                                  info.name or info.what)

        table_insert(callstack, str)
    end

    -- remove the last ';'
    local top = callstack[1]
    callstack[1] = string_sub(top, 1, string_len(top) -  1)

    local top_frame

    -- has at least one callstack
    if #callstack > 0 then
        -- like `init.lua:128:start_timer()`
        top_frame = callstack[1]
    end

    local _callstack = callstack
    callstack = {}

    -- to adjust the order of raw data of flamegraph
    for _ = 1, #_callstack do
        table_insert(callstack, table_remove(_callstack))
    end

    return top_frame, table_concat(callstack, nil)
end


return _M