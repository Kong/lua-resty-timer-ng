local utils = require("resty.timer.utils")

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_STDERR = ngx.STDERR
local ngx_EMERG = ngx.EMERG
local ngx_ALERT = ngx.ALERT
local ngx_CRIT = ngx.CRIT
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
-- luacheck: pop

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

local string_format = string.format

local table_unpack = table.unpack

local setmetatable = setmetatable
local error = error
local pcall = pcall

local LOG_FORMAT_SPAWN = "thread %s has been spawned"
local LOG_FORMAT_ERROR_SPAWN = "failed to spawn thread %s: %s"

local LOG_FORMAT_START = "thread %s has been started"
local LOG_FORMAT_EXIT = "thread %s has been exited"

local LOG_FORMAT_ERROR_INIT =
    "thread %s will exits after initializing: %s"
local LOG_FORMAT_EXIT_INIT =
    "thread %s will exits atfer initializing"
local LOG_FORMAT_EXIT_WITH_MSG_INIT =
    "thread %s will exits atfer initializing: %s"
local LOG_FORMAT_RESTART_INIT =
    "thread %s will be restarted after initializing"
local LOG_FORMAT_ERROR_BEFORE =
    "thread %s will exits after the before_callback is executed: %s"
local LOG_FORMAT_EXIT_BEFORE =
    "thread %s will exits after the before_callback body is executed"
local LOG_FORMAT_EXIT_WITH_MSG_BEFORE =
    "thread %s will exits after the before_callback body is executed: %s"
local LOG_FORMAT_RESTART_BEFORE =
    "thread %s will be restarted after the before_callback body is executed"

local LOG_FORMAT_ERROR_LOOP_BODY =
    "thread %s will exits after the loop body is executed: %s"
local LOG_FORMAT_EXIT_LOOP_BODY =
    "thread %s will exits after the loop body is executed"
local LOG_FORMAT_EXIT_WITH_MSG_LOOP_BODY =
    "thread %s will exits after the loop body is executed: %s"
local LOG_FORMAT_RESTART_LOOP_BODY =
    "thread %s will be restarted after the loop body is executed"

local LOG_FORMAT_ERROR_AFTER =
    "thread %s will exits after the after_callback is executed: %s"
local LOG_FORMAT_EXIT_AFTER =
    "thread %s will exits after the after_callback body is executed"
local LOG_FORMAT_EXIT_WITH_MSG_AFTER =
    "thread %s will exits after the after_callback body is executed: %s"
local LOG_FORMAT_RESTART_AFTER =
    "thread %s will be restarted after the after_callback body is executed"

local LOG_FORMAT_ERROR_FINALLY =
        "thread %s will exits after the finally_callback is executed: %s"
local LOG_FORMAT_EXIT_FINALLY =
        "thread %s will exits after the finally_callback is executed"
local LOG_FORMAT_EXIT_WITH_MSG_FINALLY =
    "thread %s will exits after the finally_callback is executed: %s"
local LOG_FORMAT_RESTART_FINALLY =
    "thread %s will be restarted after the finally_callback body is executed"

local ACTION_CONTINUE = 1
local ACTION_ERROR = 2
local ACTION_EXIT = 3
local ACTION_EXIT_WITH_MSG = 4
local ACTION_RESTART = 5


local _M = {
    ACTION_CONTINUE = ACTION_CONTINUE,
    ACTION_ERROR = ACTION_ERROR,
    ACTION_EXIT = ACTION_EXIT,
    ACTION_EXIT_WITH_MSG = ACTION_EXIT_WITH_MSG,
    ACTION_RESTART = ACTION_RESTART,
}

local meta_table = {
    __index = _M,
}


local function nop_init()
    return ACTION_CONTINUE
end

local function nop_before()
    return ACTION_CONTINUE
end

local function nop_loop_body()
    return ACTION_CONTINUE
end

local function nop_after()
    return ACTION_CONTINUE
end

local function nop_finally()
    return ACTION_CONTINUE
end


---exec phase_handler and handle its result
---@param self table
---@param phase_handler function self.init/before/loop_body/after/finally
---@return boolean need_to_exit_thread
local function do_phase_handler(self, phase_handler)
    local action, err = phase_handler()
    local log_format = self.log_format_map[phase_handler][action]

    if action == ACTION_CONTINUE then
        return false
    end

    if action == ACTION_ERROR then
        ngx_log(ngx_EMERG,
                string_format(log_format, self.name, err))
        return true
    end

    if action == ACTION_EXIT then
        ngx_log(ngx_NOTICE,
                string_format(log_format, self.name))
        return true
    end

    if action == ACTION_EXIT_WITH_MSG then
        ngx_log(ngx_NOTICE,
                string_format(log_format, self.name, err))
        return true
    end

    if action == ACTION_RESTART then
        ngx_log(ngx_NOTICE,
                string_format(log_format, self.name))
        self:spawn()
        return true
    end

    error("unexpected error")
end


local function callback_wrapper(self, check_worker_exiting, callback, ...)
    local ok, action_or_err, err_or_nil = pcall(callback, self.context, ...)

    if not ok then
        return ACTION_ERROR, action_or_err
    end

    local action = action_or_err
    local err = err_or_nil

    if action == ACTION_CONTINUE or
       action == ACTION_RESTART
    then
        if check_worker_exiting and ngx_worker_exiting() then
            return ACTION_EXIT_WITH_MSG, "worker exiting"
        end

        if self._kill then
            return ACTION_EXIT_WITH_MSG, "killed"
        end

        return action
    end

    if action == ACTION_EXIT then
        return action
    end

    if action == ACTION_EXIT_WITH_MSG then
        assert(err ~= nil)
        return action, err
    end

    if action == ACTION_ERROR then
        assert(err ~= nil)
        return ACTION_ERROR, err
    end

    error("unexpected error")
end


local function loop_wrapper(premature, self)
    if premature then
        return
    end

    ngx_log(ngx_NOTICE,
            string_format(LOG_FORMAT_START,
                          self.name))

    local before = self.before
    local loop_body = self.loop_body
    local after = self.after

    if not do_phase_handler(self, self.init) then
        while not ngx_worker_exiting() and not self._kill do
            if do_phase_handler(self, before) then
                break
            end

            if do_phase_handler(self, loop_body) then
                break
            end

            if do_phase_handler(self, after) then
                break
            end
        end
    end


    do_phase_handler(self, self.finally)

    ngx_log(ngx_NOTICE,
            string_format(LOG_FORMAT_EXIT,
                          self.name))
end


local function wrap_callback(self, callback, argc, argv,
                             is_check_worker_exiting)
    return function ()
        return callback_wrapper(self,
                                is_check_worker_exiting,
                                callback,
                                table_unpack(argv, 1, argc))
    end
end


function _M:spawn()
    self._kill = false
    local ok, err = ngx_timer_at(0, loop_wrapper, self)

    if not ok then
        err = string_format(LOG_FORMAT_ERROR_SPAWN,
                            self.name, err)
        ngx_log(ngx_EMERG, err)
        return false, err
    end

    ngx_log(ngx_NOTICE,
            string_format(LOG_FORMAT_SPAWN,
                          self.name))
    return true, nil
end


function _M:kill()
    self._kill = true
end


function _M.new(name, options)
    local self = {
        name = tostring(name),
        context = {},
        _kill = false,
        init = nop_init,
        before = nop_before,
        loop_body = nop_loop_body,
        after = nop_after,
        finally = nop_finally,
    }

    local check_worker_exiting = true
    local do_not_check_worker_exiting = false

    if options.init then
        self.init = wrap_callback(self,
                                  options.init.callback,
                                  options.init.argc,
                                  options.init.argv,
                                  do_not_check_worker_exiting)
    end

    if options.before then
        self.before = wrap_callback(self,
                                    options.before.callback,
                                    options.before.argc,
                                    options.before.argv,
                                    check_worker_exiting)
    end

    if options.loop_body then
        self.loop_body = wrap_callback(self,
                                       options.loop_body.callback,
                                       options.loop_body.argc,
                                       options.loop_body.argv,
                                       check_worker_exiting)
    end

    if options.after then
        self.after = wrap_callback(self,
                                   options.after.callback,
                                   options.after.argc,
                                   options.after.argv,
                                   do_not_check_worker_exiting)
    end

    if options.finally then
        self.finally = wrap_callback(self,
                                    options.finally.callback,
                                    options.finally.argc,
                                    options.finally.argv,
                                    do_not_check_worker_exiting)
    end


    self.log_format_map = {
        [self.init] = {
            [ACTION_ERROR]                  = LOG_FORMAT_ERROR_INIT,
            [ACTION_EXIT]                   = LOG_FORMAT_EXIT_INIT,
            [LOG_FORMAT_EXIT_WITH_MSG_INIT] = LOG_FORMAT_EXIT_WITH_MSG_INIT,
            [ACTION_RESTART]                = LOG_FORMAT_RESTART_INIT,
        },

        [self.before] = {
            [ACTION_ERROR]                  = LOG_FORMAT_ERROR_BEFORE,
            [ACTION_EXIT]                   = LOG_FORMAT_EXIT_BEFORE,
            [LOG_FORMAT_EXIT_WITH_MSG_INIT] = LOG_FORMAT_EXIT_WITH_MSG_BEFORE,
            [ACTION_RESTART]                = LOG_FORMAT_RESTART_BEFORE,
        },

        [self.loop_body] = {
            [ACTION_ERROR]                  = LOG_FORMAT_ERROR_LOOP_BODY,
            [ACTION_EXIT]                   = LOG_FORMAT_EXIT_LOOP_BODY,
            [LOG_FORMAT_EXIT_WITH_MSG_INIT] = LOG_FORMAT_EXIT_WITH_MSG_LOOP_BODY,
            [ACTION_RESTART]                = LOG_FORMAT_RESTART_LOOP_BODY,
        },

        [self.after] = {
            [ACTION_ERROR]                  = LOG_FORMAT_ERROR_AFTER,
            [ACTION_EXIT]                   = LOG_FORMAT_EXIT_AFTER,
            [LOG_FORMAT_EXIT_WITH_MSG_INIT] = LOG_FORMAT_EXIT_WITH_MSG_AFTER,
            [ACTION_RESTART]                = LOG_FORMAT_RESTART_AFTER,
        },

        [self.finally] = {
            [ACTION_ERROR]                  = LOG_FORMAT_ERROR_FINALLY,
            [ACTION_EXIT]                   = LOG_FORMAT_EXIT_FINALLY,
            [LOG_FORMAT_EXIT_WITH_MSG_INIT] = LOG_FORMAT_EXIT_WITH_MSG_FINALLY,
            [ACTION_RESTART]                = LOG_FORMAT_RESTART_FINALLY,
        },
    }

    return setmetatable(self, meta_table)
end


return _M