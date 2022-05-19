local super_thread_module = require("resty.timer.thread.super")
local worker_thread_module = require("resty.timer.thread.worker")

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:wake_up_super_thread()
    self.super_thread:wake_up()
end


function _M:wake_up_worker_thread()
    self.worker_thread:wake_up()
end


---spawn super_thread, and all worker threads
---@return boolean ok ok?
---@return string err_msg
function _M:spawn()
    local ok, err
    ok, err = self.super_thread:spawn()

    if not ok then
        return false, err
    end

    ok, err = self.worker_thread:spawn()

    if not ok then
        self.super_thread:kill()
        self.worker_thread:kill()
        return false, err
    end

    return true, nil
end


---kill super_thread, and all worker threads
function _M:kill()
    self.super_thread:kill()
    self.worker_thread:kill()
end


function _M.new(timer_sys)
    local super_thread = super_thread_module.new(timer_sys)
    local worker_thread = worker_thread_module.new(timer_sys,
                                                   timer_sys.opt.threads)

    local self = {
        super_thread = super_thread,
        worker_thread = worker_thread,
    }

    super_thread:set_spawn_worker_thread_callback(function ()
        worker_thread:spawn()
    end)

    super_thread:set_wake_up_worker_thread_callback(function ()
        worker_thread:wake_up()
    end)

    worker_thread:set_wake_up_super_thread_callback(function ()
        super_thread:wake_up()
    end)

    return setmetatable(self, meta_table)
end

return _M