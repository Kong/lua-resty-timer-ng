local semaphore = require("ngx.semaphore")
local utils = require("resty.timer.utils")

local string_format = string.format

local table_unpack = table.unpack

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local ngx_NOTICE = ngx.NOTICE
-- luacheck: pop

local setmetatable = setmetatable
local tostring = tostring

local assert = utils.assert

local _M = {}

local meta_table = {
    __index = _M,
}


local function callback_wraper(premature, self)
    ngx_log(ngx_NOTICE, string_format("thread %s has been started",
                                      self.id))

    if premature then
        ngx_log(ngx_NOTICE, string_format(
            "exit thread %s due to premature",
            self.id
        ))
        return
    end

    local restart_thread_after_runs = self.restart_thread_after_runs
    local begin_kill_semaphore = self.begin_kill_semaphore
    local self_callback = self.callback
    local argc = self.argc
    local argv = self.argv

    while not ngx_worker_exiting() do
        local ok, err = begin_kill_semaphore:wait(0)

        if ok then
            break
        end

        if err ~= "timeout" then
            ngx_log(ngx_ERR,
                "semaphore:wait() failed: " .. err)
            -- self.begin_destroy_semaphore = semaphore.new(0)
            -- begin_destroy_semaphore = self.begin_destroy_semaphore
        end

        self.counter.runs = self.counter.runs + 1
        self_callback(table_unpack(argv, 1, argc))

        if self.counter.runs > restart_thread_after_runs then
            -- Since the native timer only releases resources
            -- when it is destroyed,
            -- including resources created by `job:execute()`
            -- it needs to be destroyed and recreated periodically.
            ok, err = ngx_timer_at(0, callback_wraper, self)

            if not ok then
                ngx_log(ngx_ERR, string_format(
                    "failed to restart thread %s: %s",
                    self.id, err
                ))

            else
                break
            end

        end
    end

    self.finish_kill_semaphore:post(1)

    ngx_log(ngx_NOTICE, string_format(
        "exit thread %s",
        self.id
    ))
end


function _M:spawn()
    local ok, err = ngx_timer_at(0, callback_wraper, self)
    return ok ~= nil and ok ~= false, err
end


function _M:kill(timeout)
    assert(type(timeout) == "number")

    self.begin_kill_semaphore:post(1)
    local ok, err = self.finish_kill_semaphore:wait(timeout)

    if ok then
        return true, nil
    end

    return false, string_format("faled to kill thread %s: %s",
                                self.id, err)
end


function _M.new(id, restart_thread_after_runs, callback, ...)
    local self = {
        id = tostring(id),
        restart_thread_after_runs = restart_thread_after_runs,
        callback = callback,
        begin_kill_semaphore = semaphore.new(0),
        finish_kill_semaphore = semaphore.new(0),
        argc = select("#", ...),
        argv = { ... },
        counter = {
            runs = 0,
        },
    }

    return setmetatable(self, meta_table)
end


return _M