local store = require("resty.timerng.store")

local math_floor = math.floor

local table_insert = table.insert
local table_concat = table.concat

local ipairs = ipairs

local STORE_NAMESPACE_SYS = "timer-ng-sys"
local STORE_NAMESPACE_RUNNING = "timer-ng-running"
local STORE_NAMESPACE_PENDING = "timer-ng-pending"
local STORE_NAMESPACE_ELASPED_TIME = "timer-ng-elapsed-time"

local _M = {}

local meta_table = {
    __index = _M,
}


function _M:on_job_create(job)
    self.store:increase(STORE_NAMESPACE_SYS, "total")
end


function _M:on_job_pending(job)
    self.store:increase(STORE_NAMESPACE_SYS, "pending")

    if not job.meta then
        return
    end

    local fold_callstack = job.meta.callstack

    self.store:increase(STORE_NAMESPACE_PENDING, fold_callstack)
end


function _M:on_job_cancel(job)
    self.store:safe_decrease(STORE_NAMESPACE_SYS, "total")

    if not job.meta then
        return
    end

    local fold_callstack = job.meta.callstack
    local elapsed_time = job.stats.runs * job.stats.elapsed_time.avg

    self.store:increase(STORE_NAMESPACE_ELASPED_TIME,
                        fold_callstack, elapsed_time)
end


function _M:before_job_execute(job)
    self.store:increase(STORE_NAMESPACE_SYS, "running")
    self.store:safe_decrease(STORE_NAMESPACE_SYS, "pending")

    if not job.meta then
        return
    end

    local fold_callstack = job.meta.callstack

    self.store:safe_decrease(STORE_NAMESPACE_PENDING, fold_callstack)
    self.store:increase(STORE_NAMESPACE_RUNNING, fold_callstack, 1)
end


function _M:after_job_execute(job)
    self.store:safe_decrease(STORE_NAMESPACE_SYS, "running")
    self.store:increase(STORE_NAMESPACE_SYS, "runs")

    if not job.meta then
        return
    end

    local fold_callstack = job.meta.callstack

    self.store:safe_decrease(STORE_NAMESPACE_RUNNING, fold_callstack)
end


function _M:sys_stats()
    local runs = self.store:get(STORE_NAMESPACE_SYS, "runs")
    local total = self.store:get(STORE_NAMESPACE_SYS, "total")
    local running = self.store:get(STORE_NAMESPACE_SYS, "running")
    local pending = self.store:get(STORE_NAMESPACE_SYS, "pending")
    local waiting = total - running - pending

    return {
        runs = runs,
        total = total,
        running = running,
        pending = pending,
        waiting = waiting,
    }
end


function _M:raw_flamegraph()
    local flamegraph = {
        running = {},
        pending = {},
        elapsed_time = {},
    }

    local backtraces = self.store:keys(STORE_NAMESPACE_RUNNING)

    for _, backtrace in ipairs(backtraces) do
        local count = self.store:get(STORE_NAMESPACE_RUNNING,
                                     backtrace)

        if count <= 0 then
            goto continue
        end

        table_insert(flamegraph.running, backtrace)
        table_insert(flamegraph.running, " ")
        table_insert(flamegraph.running, count)
        table_insert(flamegraph.running, "\n")

        ::continue::
    end

    backtraces = self.store:keys(STORE_NAMESPACE_PENDING)

    for _, backtrace in ipairs(backtraces) do
        local count = self.store:get(STORE_NAMESPACE_PENDING,
                                     backtrace)

        if count <= 0 then
            goto continue
        end

        table_insert(flamegraph.pending, backtrace)
        table_insert(flamegraph.pending, " ")
        table_insert(flamegraph.pending, math_floor(count * 1000))
        table_insert(flamegraph.pending, "\n")

        ::continue::
    end

    backtraces = self.store:keys(STORE_NAMESPACE_ELASPED_TIME)

    for _, backtrace in ipairs(backtraces) do
        local elapsed_time =
            self.store:get(STORE_NAMESPACE_ELASPED_TIME,
                           backtrace)

        if elapsed_time <= 0 then
            goto continue
        end

        table_insert(flamegraph.elapsed_time, backtrace)
        table_insert(flamegraph.elapsed_time, " ")
        table_insert(flamegraph.elapsed_time, math_floor(elapsed_time * 1000))
        table_insert(flamegraph.elapsed_time, "\n")

        ::continue::
    end

    flamegraph.running = table_concat(flamegraph.running)
    flamegraph.pending = table_concat(flamegraph.pending)
    flamegraph.elapsed_time = table_concat(flamegraph.elapsed_time)

    return flamegraph
end


function _M.new()
    local self = {
        store = store.new(),
    }

    self.store:new_namespace(STORE_NAMESPACE_SYS,
                        store.STORE_TYPE_GENERNAL)

    self.store:new_namespace(STORE_NAMESPACE_RUNNING,
                        store.STORE_TYPE_LRU)

    self.store:new_namespace(STORE_NAMESPACE_PENDING,
                        store.STORE_TYPE_LRU)

    self.store:new_namespace(STORE_NAMESPACE_ELASPED_TIME,
                        store.STORE_TYPE_LRU)

    self.store:set(STORE_NAMESPACE_SYS, "runs", 0)
    self.store:set(STORE_NAMESPACE_SYS, "total", 0)
    self.store:set(STORE_NAMESPACE_SYS, "running", 0)
    self.store:set(STORE_NAMESPACE_SYS, "pending", 0)

    return setmetatable(self, meta_table)
end


return _M
