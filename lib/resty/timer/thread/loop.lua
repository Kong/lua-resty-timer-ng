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

local ACTION_CONTINUE = 1
local ACTION_ERROR = 2
local ACTION_EXIT = 3
local ACTION_EXIT_WITH_MSG = 4


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


---make log message
---@param self table
---@param phase string init | before | loop_body | after | finally
---@param action number _M.ACTION_*
---@param msg? string message
---@return string log_string
local function make_log_msg(self, phase, action, msg)
    if action == ACTION_EXIT then
        return string_format(
            "[timer] thread %s will exits after the %s phase was executed",
            self.name,
            phase
        )
    end

    if action == ACTION_ERROR or action == ACTION_EXIT_WITH_MSG then
        return string_format(
            "[timer] thread %s will exits after the %s phase was executed: %s",
            self.name,
            phase,
            msg
        )
    end

    error("unexpected error")
end


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

    if action == ACTION_CONTINUE
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

    if action == ACTION_CONTINUE then
        return false
    end

    if action == ACTION_ERROR then
        ngx_log(ngx_EMERG, make_log_msg(self, phase, action, err))
        return true
    end

    if action == ACTION_EXIT then
        ngx_log(ngx_NOTICE, make_log_msg(self, phase, action, nil))
        return true
    end

    if action == ACTION_EXIT_WITH_MSG then
        ngx_log(ngx_NOTICE, make_log_msg(self, phase, action, err))
        return true
    end

    error("unexpected error")
end


local function loop_wrapper(premature, self)
    if premature then
        return
    end

    ngx_log(ngx_NOTICE,
            string_format("[timer] thread %s has been started",
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
            string_format("[timer] thread %s has been exited",
                          self.name))
end


function _M:spawn()
    self._kill = false
    local ok, err = ngx_timer_at(0, loop_wrapper, self)

    if not ok then
        err = string_format("failed to spawn thread %s: %s",
                            self.name, err)
        ngx_log(ngx_EMERG, err)
        return false, err
    end

    ngx_log(ngx_NOTICE,
            string_format("[timer] thread %s has been spawned",
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
        context = {
            self = nil
        },
        _kill = false
    }

    self.context.self = self

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