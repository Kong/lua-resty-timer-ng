local ngx_log = ngx.log
local ngx_EMERG = ngx.EMERG
local ngx_NOTICE = ngx.NOTICE

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

local string_format = string.format

local table_unpack = table.unpack

local setmetatable = setmetatable
local error = error
local pcall = pcall

local LOG_FORMAT_SPAWN = "[timer] thread %s has been spawned"
local LOG_FORMAT_ERROR_SPAWN = "failed to spawn thread %s: %s"

local LOG_FORMAT_START = "[timer] thread %s has been started"
local LOG_FORMAT_EXIT = "[timer] thread %s has been exited"

local LOG_FORMAT_ERROR_INIT =
    "[timer] thread %s will exits after initializing: %s"
local LOG_FORMAT_EXIT_INIT =
    "[timer] thread %s will exits atfer initializing"
local LOG_FORMAT_EXIT_WITH_MSG_INIT =
    "[timer] thread %s will exits atfer initializing: %s"
local LOG_FORMAT_RESTART_INIT =
    "[timer] thread %s will be restarted after initializing"
local LOG_FORMAT_ERROR_BEFORE =
    "[timer] thread %s will exits after the before_callback is executed: %s"
local LOG_FORMAT_EXIT_BEFORE =
    "[timer] thread %s will exits after the before_callback is executed"
local LOG_FORMAT_EXIT_WITH_MSG_BEFORE =
    "[timer] thread %s will exits after the before_callback is executed: %s"
local LOG_FORMAT_RESTART_BEFORE =
    "[timer] thread %s will be restarted after the before_callback is executed"

local LOG_FORMAT_ERROR_LOOP_BODY =
    "[timer] thread %s will exits after the loop body is executed: %s"
local LOG_FORMAT_EXIT_LOOP_BODY =
    "[timer] thread %s will exits after the loop body is executed"
local LOG_FORMAT_EXIT_WITH_MSG_LOOP_BODY =
    "[timer] thread %s will exits after the loop body is executed: %s"
local LOG_FORMAT_RESTART_LOOP_BODY =
    "[timer] thread %s will be restarted after the loop body is executed"

local LOG_FORMAT_ERROR_AFTER =
    "[timer] thread %s will exits after the after_callback is executed: %s"
local LOG_FORMAT_EXIT_AFTER =
    "[timer] thread %s will exits after the after_callback is executed"
local LOG_FORMAT_EXIT_WITH_MSG_AFTER =
    "[timer] thread %s will exits after the after_callback is executed: %s"
local LOG_FORMAT_RESTART_AFTER =
    "[timer] thread %s will be restarted after the after_callback is executed"

local LOG_FORMAT_ERROR_FINALLY =
    "[timer] thread %s will exits after the finally_callback is executed: %s"
local LOG_FORMAT_EXIT_FINALLY =
    "[timer] thread %s will exits after the finally_callback is executed"
local LOG_FORMAT_EXIT_WITH_MSG_FINALLY =
    "[timer] thread %s will exits after the finally_callback is executed: %s"
local LOG_FORMAT_RESTART_FINALLY =
    "[timer] thread %s will be restarted after the finally_callback is executed"

local ACTION_CONTINUE = 1
local ACTION_ERROR = 2
local ACTION_EXIT = 3
local ACTION_EXIT_WITH_MSG = 4
local ACTION_RESTART = 5

local LOG_FORMAT_MAP = {
    init = {
        [ACTION_ERROR]              = LOG_FORMAT_ERROR_INIT,
        [ACTION_EXIT]               = LOG_FORMAT_EXIT_INIT,
        [ACTION_EXIT_WITH_MSG]      = LOG_FORMAT_EXIT_WITH_MSG_INIT,
        [ACTION_RESTART]            = LOG_FORMAT_RESTART_INIT,
    },

    before = {
        [ACTION_ERROR]              = LOG_FORMAT_ERROR_BEFORE,
        [ACTION_EXIT]               = LOG_FORMAT_EXIT_BEFORE,
        [ACTION_EXIT_WITH_MSG]      = LOG_FORMAT_EXIT_WITH_MSG_BEFORE,
        [ACTION_RESTART]            = LOG_FORMAT_RESTART_BEFORE,
    },

    loop_body = {
        [ACTION_ERROR]              = LOG_FORMAT_ERROR_LOOP_BODY,
        [ACTION_EXIT]               = LOG_FORMAT_EXIT_LOOP_BODY,
        [ACTION_EXIT_WITH_MSG]      = LOG_FORMAT_EXIT_WITH_MSG_LOOP_BODY,
        [ACTION_RESTART]            = LOG_FORMAT_RESTART_LOOP_BODY,
    },

    after = {
        [ACTION_ERROR]              = LOG_FORMAT_ERROR_AFTER,
        [ACTION_EXIT]               = LOG_FORMAT_EXIT_AFTER,
        [ACTION_EXIT_WITH_MSG]      = LOG_FORMAT_EXIT_WITH_MSG_AFTER,
        [ACTION_RESTART]            = LOG_FORMAT_RESTART_AFTER,
    },

    finally = {
        [ACTION_ERROR]              = LOG_FORMAT_ERROR_FINALLY,
        [ACTION_EXIT]               = LOG_FORMAT_EXIT_FINALLY,
        [ACTION_EXIT_WITH_MSG]      = LOG_FORMAT_EXIT_WITH_MSG_FINALLY,
        [ACTION_RESTART]            = LOG_FORMAT_RESTART_FINALLY,
    },
}

local NEED_CHECK_WORKER_EIXTING = {
    init = false,
    before = true,
    loop_body = true,
    after = false,
    finally = false,
}



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


local PAHSE_HANDLERS = {
    init = nop_init,
    before = nop_before,
    loop_body = nop_loop_body,
    after = nop_after,
    finally = nop_finally,
}


---@param self table self
---@param phase string init | before | loop_body | after | finally
---@return integer action
---@return string message
local function phase_handler_wrapper(self, phase)
    local ok, action_or_err, err_or_nil =
        pcall(self[phase].callback,
              self.context,
              table_unpack(self[phase].argv, 1, self[phase].argc))

    if not ok then
        return ACTION_ERROR, action_or_err
    end

    local action = action_or_err
    local err = err_or_nil

    if action == ACTION_CONTINUE or
       action == ACTION_RESTART
    then
        if  self[phase].need_check_worker_exiting and
            ngx_worker_exiting()
        then
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


---exec phase_handler and handle its result
---@param self table
---@param phase string init/before/loop_body/after/finally
---@return boolean need_to_exit_thread
local function do_phase_handler(self, phase)
    local action, err = phase_handler_wrapper(self, phase)
    local log_format = LOG_FORMAT_MAP[phase][action]

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


local function loop_wrapper(premature, self)
    if premature then
        return
    end

    ngx_log(ngx_NOTICE,
            string_format(LOG_FORMAT_START,
                          self.name))

    if not do_phase_handler(self, "init") then
        while not ngx_worker_exiting() and not self._kill do
            if do_phase_handler(self, "before") then
                break
            end

            if do_phase_handler(self, "loop_body") then
                break
            end

            if do_phase_handler(self, "after") then
                break
            end
        end
    end


    do_phase_handler(self, "finally")

    ngx_log(ngx_NOTICE,
            string_format(LOG_FORMAT_EXIT,
                          self.name))
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
    assert(options ~= nil)

    local self = {
        name = tostring(name),
        context = {},
        _kill = false
    }

    for phase, default_handler in pairs(PAHSE_HANDLERS) do
        self[phase] = {}

        self[phase].need_check_worker_exiting
                = NEED_CHECK_WORKER_EIXTING[phase]

        if not options[phase] then
            self[phase].argc = 0
            self[phase].argv = {}
            self[phase].callback = default_handler

        else
            self[phase].argc = options[phase].argc
            self[phase].argv = options[phase].argv
            self[phase].callback = options[phase].callback
        end
    end

    return setmetatable(self, meta_table)
end


return _M