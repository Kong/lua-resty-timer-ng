local utils = require("resty.timer.utils")

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local utils_table_new = utils.table_new
local utils_table_clear = utils.table_clear

local table_insert = table.insert
local table_remove = table.remove

local setmetatable = setmetatable

local array_pool = {}

local _M = {}

local meta_table = {
    __index = _M
}


function _M.next(array, index)
    if index == nil then
        index = 0
    end

    if array.nelts < index then
        return nil
    end

    if index + 1 > array.nelts then
        return nil
    end

    return index + 1, array.elts[index]
end


function _M:is_empty()
    return self.nelts == 0
end


function _M:pop()
    if self.nelts == 0 then
        return nil
    end

    local value = self.elts[self.nelts]
    self.elts[self.nelts] = nil
    self.nelts = self.nelts - 1
    return value
end


function _M:push(value)
    self.elts[self.nelts + 1] = value
    self.nelts = self.nelts + 1
end


function _M.new(n)
    if n == nil then
        n = 8
    end

    local self = table_remove(array_pool)

    if self then
        return self
    end

    self = {
        elts = utils_table_new(n, 0),
        nelts = 0,
    }

    return setmetatable(self, meta_table)
end


function _M:release()
    utils_table_clear(self.elts)
    self.nelts = 0
    table_insert(array_pool, self)
end


function _M.merge(dst, src)
    if src == nil or src.nelts == 0 then
        return
    end

    for i = 1, src.nelts do
        dst:push(src.elts[i])
    end
end

return _M
