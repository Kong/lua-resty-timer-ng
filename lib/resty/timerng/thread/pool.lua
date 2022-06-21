local semaphore = require("ngx.semaphore")
local contants = require("resty.timerng.constants")
local loop = require("resty.timerng.thread.loop")
local array = require("resty.timerng.array")
local store = require("resty.timerng.store")

local ngx_log = ngx.log
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR

local ngx_now = ngx.now

local math_floor = math.floor

local table_unpack = table.unpack

local string_format = string.format
local setmetatable = setmetatable

local CONTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN =
    contants.TOLERANCE_OF_GRACEFUL_SHUTDOWN

local LOG_INTERVAL = 60

local STORE_NAMESPACE_AVG_LOAD = "timer-ng-threadpool-avg-load"
local STORE_NAMESPACE_AVG_ALIVE = "timer-ng-threadpool-avg-alive"
local STORE_NAMESPACE_AVG_RUNNING = "timer-ng-threadpool-avg-running"
local STORE_NAMESPACE_AVG_IDLE = "timer-ng-threadpool-avg-idle"
local STORE_NAMESPACE_AVG_PENDING = "timer-ng-threadpool-avg-pending"

local _M = {}

local meta_table = {
    __index = _M,
}


local function init_instance(self, context)
    local instance_name = context.self.name
    local instance = {
        name = instance_name,
        running = true,
    }

    self.alive_threads[instance_name] = instance
    self.alive_threads_count = self.alive_threads_count + 1
end


local function get_instance(self, context)
    return self.alive_threads[context.self.name]
end


local function remove_instance(self, context)
    local instance_name = context.self.name
    self.alive_threads[instance_name] = nil
    self.alive_threads_count = self.alive_threads_count - 1
end


---set the instance status
---@param self table self
---@param context table context
---@param ... string status (`running` or `idle`)
local function set_instance_status(self, context, ...)
    local argv = { ... }
    local instance = get_instance(self, context)

    for _, status in ipairs(argv) do
        if status == "running" then
            instance.running = true
            self.running_threads_count = self.running_threads_count + 1
            goto continue
        end

        if status == "idle" then
            instance.running = false
            self.running_threads_count = self.running_threads_count - 1
            goto continue
        end

        error(string_format("invalid status: %s", status))

        ::continue::
    end
end


local function wait_instance_woken_up(self, context)
    set_instance_status(self, context, "idle")

    local ok, err
    local start = ngx_now()

    repeat
        ok, err =
            self.wake_up_semaphore:wait(CONTANTS_TOLERANCE_OF_GRACEFUL_SHUTDOWN)

        if self._destroy then
            remove_instance(self, context)
            return false, "destroyed"
        end

        if not ok then
            if err ~= "timeout" then
                ngx_log(ngx_ERR, "[timer-ng] failed to wait semaphore: ", err)
                self.wake_up_semaphore = semaphore.new(self.max_threads)
                return false, err
            end

            if ngx_now() - start > 10 then
                return false, "timeout"
            end
        end
    until ok

    set_instance_status(self, context, "running")

    return true
end


local function init_phase_handler(context, self)
    if self.alive_threads_count >= self.max_threads then
        return loop.ACTION_EXIT
    end

    init_instance(self, context)
    set_instance_status(self, context, "running")
    return loop.ACTION_CONTINUE
end


local function loop_body_phase_handler(context, self)
    local queue = self.queue

    while not queue:is_empty() do
        local task = queue:pop_right()
        task.callback(table_unpack(task.argv, 1, task.argc))
    end

    return loop.ACTION_CONTINUE
end


local function after_phase_handler(context, self)
    local ok, err = wait_instance_woken_up(self, context)

    if not ok then
        if err == "destroyed" then
            return loop.ACTION_EXIT
        end

        if err == "timeout" then
            if self.alive_threads_count > self.min_threads then
                return loop.ACTION_EXIT
            end

            return loop.ACTION_CONTINUE
        end

        return loop.ACTION_ERROR, err
    end

    return loop.ACTION_CONTINUE
end


local function finally_phase_handler(context, self)
    if get_instance(self, context) then
        remove_instance(self, context)
    end

    return loop.ACTION_CONTINUE
end


local function wake_up_instances(self)
    local wake_up_semaphore = self.wake_up_semaphore
    local delta = self.max_threads - wake_up_semaphore:count()

    if delta > 0 then
        wake_up_semaphore:post(delta)
    end
end


function _M:submit(callback, argc, ...)
    local max_threads = self.max_threads

    local queue = self.queue

    local stats = self:stats()
    local alive_threads_count = stats.alive_threads_count
    local idle_threads_count = stats.idle_threads_count

    self.store:append(STORE_NAMESPACE_AVG_PENDING, stats.queue_length)
    self.store:append(STORE_NAMESPACE_AVG_LOAD, stats.load)
    self.store:append(STORE_NAMESPACE_AVG_ALIVE, alive_threads_count)
    self.store:append(STORE_NAMESPACE_AVG_IDLE, idle_threads_count)
    self.store:append(STORE_NAMESPACE_AVG_RUNNING, stats.running_threads_count)

    local now = ngx_now()

    if now - self.last_log_time > LOG_INTERVAL then
        self.last_log_time = now

        local load_avg = self.store:average(STORE_NAMESPACE_AVG_LOAD)
        local alive_avg = self.store:average(STORE_NAMESPACE_AVG_ALIVE)
        local pending_avg = self.store:average(STORE_NAMESPACE_AVG_PENDING)
        local idle_avg = self.store:average(STORE_NAMESPACE_AVG_IDLE)
        local running_avg = self.store:average(STORE_NAMESPACE_AVG_RUNNING)

        local log = string_format(
            "load: %f, alive: %f, pending: %f, idle: %f, running: %f",
            load_avg, alive_avg, pending_avg, idle_avg, running_avg
        )

        if load_avg >= 1.5 then
            ngx_log(ngx_WARN, "[timer-ng] overload: " .. log)
            ngx_log(ngx_WARN, "[timer-ng] overload: " .. log)

        else
            ngx_log(ngx_INFO, "[timer-ng] " .. log)
            ngx_log(ngx_INFO, "[timer-ng] " .. log)
        end
    end


    if idle_threads_count < 1 and alive_threads_count < max_threads then
        local thread_name = string_format("pool_thread#%d#%d",
                                          math_floor(ngx_now() * 1000),
                                          self.name_counter)

        self.name_counter = self.name_counter + 1
        local thread = loop.new(thread_name, self.thread_template)
        thread:spawn()
    end

    queue:push_left({
        callback = callback,
        argc = argc,
        argv = { ... },
    })

    wake_up_instances(self)
end


function _M:stats()
    local alive_threads_count = self.alive_threads_count
    local running_threads_count = self.running_threads_count
    local idle_threads_count = alive_threads_count - running_threads_count
    local queue_length = self.queue:length()

    local load

    if alive_threads_count == 0 then
        load = 0

    else
        load = (queue_length + running_threads_count) / alive_threads_count
    end

    return {
        alive_threads_count = alive_threads_count,
        running_threads_count = running_threads_count,
        idle_threads_count = idle_threads_count,
        queue_length = queue_length,
        load = load,
    }
end


function _M:start()
    local thread_template = self.thread_template

    for _ = 1, self.min_threads do
        local name = string_format(
            "pool_thread#%d#%d",
            math_floor(ngx_now() * 1000),
            self.name_counter)

        self.name_counter = self.name_counter + 1

        local thread = loop.new(name, thread_template)

        local ok, err = thread:spawn()

        if not ok then
            return false, err
        end
    end

    return true, nil
end


function _M:destroy()
    self._destroy = true
    self.wake_up_semaphore:post(self.max_threads * 2)
end


function _M.new(min_threads, max_threads)
    local self = {
        -- thread_option = {},
        min_threads = min_threads,
        max_threads = max_threads,

        alive_threads = {},
        alive_threads_count = 0,

        running_threads_count = 0,

        queue = array.new(128),

        wake_up_semaphore = semaphore.new(0),

        name_counter = 0,

        last_log_time = 0,

        store = store.new(),

        _destroy = false,
    }

    self.thread_template = {
        init = {
            argc = 1,
            argv = { self },
            callback = init_phase_handler,
        },
        loop_body = {
            argc = 1,
            argv = { self },
            callback = loop_body_phase_handler,
        },
        after = {
            argc = 1,
            argv = { self },
            callback = after_phase_handler,
        },
        finally = {
            argc = 1,
            argv = { self },
            callback = finally_phase_handler,
        },
    }

    self.store:new_namespace(STORE_NAMESPACE_AVG_LOAD,
                             store.STORE_TYPE_AVERAGE, 8192)

    self.store:new_namespace(STORE_NAMESPACE_AVG_ALIVE,
                             store.STORE_TYPE_AVERAGE, 8192)

    self.store:new_namespace(STORE_NAMESPACE_AVG_RUNNING,
                             store.STORE_TYPE_AVERAGE, 8192)

    self.store:new_namespace(STORE_NAMESPACE_AVG_IDLE,
                             store.STORE_TYPE_AVERAGE, 8192)

    self.store:new_namespace(STORE_NAMESPACE_AVG_PENDING,
                             store.STORE_TYPE_AVERAGE, 8192)

    return setmetatable(self, meta_table)
end


return _M
