-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:get_cur_pointer()
    return self.pointer
end


function _M:cal_pointer(pointer, offset)
    local nelts = self.nelts
    local p = pointer
    local old = p

    p = (p + offset) % (nelts + 1)

    if old + offset > nelts then
        return p + 1, true
    end

    return p, false
end


function _M:insert(pointer, job)
    assert(self.array)
    assert(pointer > 0)

    local _job = self.array[pointer][job.name]

    if not _job or not _job:is_runable() then
        self.array[pointer][job.name] = job

    else
        return false, "already exists job"
    end

    return true, nil
end


function _M:move_to_next()
    local pointer, is_move_to_end = self:cal_pointer(self.pointer, 1)
    self.pointer = pointer

    return self.array[self.pointer], is_move_to_end
end


function _M:get_jobs()
    return self.array[self.pointer]
end


function _M:get_jobs_by_pointer(pointer)
    return self.array[pointer]
end


function _M.new(nelts)
    local self = {
        pointer = 1,
        nelts = nelts,
        array = {},
    }

    for i = 1, self.nelts do
        self.array[i] = setmetatable({ }, { __mode = "v" })
    end

    return setmetatable(self, meta_table)
end


return _M