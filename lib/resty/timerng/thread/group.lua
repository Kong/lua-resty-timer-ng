local super_thread_module = require("resty.timerng.thread.super")
local thread_pool_module = require("resty.timerng.thread.pool")
local wheel_group_module = require("resty.timerng.wheel.group")

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function handle_job(self, job)
    local stat = self.timer_sys.stat
    local wheel_group = self.wheel_group

    local is_runnable = job:is_runnable()

    stat:before_job_execute(job)
    job:execute()
    stat:after_job_execute(job)

    if not is_runnable then
        return
    end

    if job:is_oneshot() then
        self.timer_sys:cancel(job.name)
        return
    end

    if job:is_runnable() then
        wheel_group:sync_time()
        job:re_cal_next_pointer(wheel_group)
        wheel_group:insert_job(job)

        local _, need_wake_up = wheel_group:update_earliest_expiry_time()

        if need_wake_up then
            self.super_thread:wake_up()
        end
    end
end


function _M:submit(job)
    self.thread_pool:submit(handle_job, 2, self, job)
end


function _M:wake_up_super_thread()
    self.super_thread:wake_up()
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

    ok, err = self.thread_pool:start()

    if not ok then
        self.super_thread:kill()
        self.thread_pool:destroy()
        return false, err
    end

    return true, nil
end


---kill super_thread, and all worker threads
function _M:kill()
    self.super_thread:kill()
    self.thread_pool:destroy()
end


function _M.new(timer_sys)
    local super_thread = super_thread_module.new(timer_sys)
    local thread_pool = thread_pool_module.new(timer_sys.opt.min_threads,
                                               timer_sys.opt.max_threads)

    local self = {
        timer_sys = timer_sys,
        super_thread = super_thread,
        thread_pool = thread_pool,
    }

    local on_expire = function(job)
        timer_sys.stat:on_job_pending(job)
        self:submit(job)
    end

    self.wheel_group = wheel_group_module.new(timer_sys.opt.wheel_setting,
                                              timer_sys.opt.resolution,
                                              on_expire)

    return setmetatable(self, meta_table)
end

return _M