local utils_table_new = require("resty.timerng.utils").table_new

local error = error
local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:length()
    return self.last - self.first + 1
end



function _M:is_empty()
    return self.first > self.last
end


function _M:push_left (value)
    local first = self.first - 1
    self.first = first
    self.elts[first] = value
end


function _M:push_right(value)
    local last = self.last + 1
    self.last = last
    self.elts[last] = value
end


function _M:pop_left ()
    local first = self.first

    if first > self.last then
        error("list is empty")
    end

    local value = self.elts[first]
    self.elts[first] = nil
    self.first = first + 1
    return value
end


function _M:pop_right()
    local last = self.last

    if self.first > last then
        error("list is empty")
    end

    local value = self.elts[last]
    self.elts[last] = nil
    self.last = last - 1
    return value
end


function _M.new(n)
    if n == nil then
        n = 8
    end

    local self = {
        elts = utils_table_new(n, 0),
        first = 0,
        last = -1,
    }

    return setmetatable(self, meta_table)
end


return _M
