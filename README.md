# lua-resty-timer-ng

## Status

This library is under development.

https://github.com/Kong/kong-madr/pull/28

## Synopsis

```nginx
http {
    init_worker_by_lua_block {
        local timer_module = require("resty.timer")
        local timer_sys = { }

        local options = {
            threads = 10,                           -- restart a timer after a certain number of this timer triggers
            restart_thread_after_runs = 50,
        }
        timer_module.configure(timer_sys, options)

        -- ‘premature’ is used to be compatible with existing callback functions and will be removed in the future
        local fuction callback_once(premature, ...)
            -- do something
            ngx.log(ngx.ERR, "in timer example-once")
        end

        local function callback_every(premature, ...)
            -- do something
            ngx.log(ngx.ERR, "in timer example-every")
        end

        -- run after 100 ms
        timer_sys:once("example-once", callback_once, 0.1)

        -- run every 1s
        timer_sys:every("example-every", callback_every, 1)
    }
}
```

## Description

This library is implemented using the timer wheel algorithm, 
which uses the small number of timers created by Openresty API `ngx.timer.at` to manage a large number of tasks.

* Efficiently, create, pause, start and cancel a timer takes O(1) time.
* Concurrency control, you can limit the number of threads.
* Easy to debug
    * Get statistics such as maximum, minimum, average, and variance of the runtime for each timer.
    * Some information that is useful for debugging, such as where the timer was created and the call stack at that time.
* If the expiration time is greater than 24 hours then the native timer is used.
* If the expiration time is less than 100ms and not equal to `0` then the native timer is used.

## Statistics

The system records the following information:

* The maximum, minimum, average, and variance of the running time of each timer.
* The location of each timer created, such as call stack.


## History

Versioning is strictly based on [Semantic Versioning](https://semver.org/)

## Methods

### configure

**syntax**: *ok, err = timer_module.configure(timer_sys, options?)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Configure the timer system.

* `timer_module`: `require("resty.timer")`
* `timer_sys`: A table, which will be initialized.

For example

```lua
local timer_module = require("resty.timer")
local timer_sys = { }
timer_module.configure(timer_sys, {
    -- number of threads
    threads = 10,

    -- restart the LWP after it has run ‘recreate_interval’ tasks.
    recreate_interval = 50
})
```


### start

**syntax**: *ok, err = timer_module.start(timer_sys)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Start the timer system.

* `timer_module`: `require("resty.timer")`
* `timer_sys`: A table initialized by `configure`.


### freeze

**syntax**: *timer_module.freeze(timer_sys)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Suspend the timer system and the expiration of each timer will be frozen.

* `timer_module`: `require("resty.timer")`
* `timer_sys`: A table initialized by `configure`.


### once

**syntax**: *name_or_false, err = timer:once(name, callback, delay, ...)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Create a once timer. You must call this method after you have called `timer:start()`.
If you have called `timer:pause()`, you must call this function after you have called `timer:start()`.

* name: The name of this timer, or if it is set to `nil`, a random name will be generated.
* callback: A callback function will be called when this timer expired, `function callback(premature, ...)`.
* delay: The expiration of this timer.


### every

**syntax**: *name_or_false, err = timer:every(name, callback, interval, ...)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Create a recurrent timer. You must call this method after you have called `timer:start()`.
If you have called `timer:pause()`, you must call this function after you have called `timer:start()`.

* name: The name of this timer, or if it is set to `nil`, a random name will be generated.
* callback: A callback function will be called when this timer expired, `function callback(premature, ...)`.
* interval: The expiration of this timer.


### run

**syntax**: *ok, err = timer:run(name)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Start a timer that has been paused and resets its expiration.

* name: The name of this timer.


### pause

**syntax**: *ok, err = timer:pause(name)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Pause a timer that has been started.

* name: The name of this timer.


### cancel

**syntax**: *ok, err = timer:cancel(name)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Cancel a timer.

* name: The name of this timer.


### unconfigure

**syntax**: *timer_module.unconfigure(timer_sys)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Cancel all timers, after which you will need to call `configure` again to continue using this library.

* `timer_module`: `require("resty.timer")`
* `timer_sys`: A table initialized by `configure`.


### stats

**syntax**: info, err = timer_module.stats(timer_sys)

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**


Get the statistics of the system.

* `timer_module`: `require("resty.timer")`
* `timer_sys`: A table initialized by `configure`.

For example:

```lua
local info, err = timer:stats()

if not info then
    -- error
end

-- info.sys = {
--     running = [number],      number of running timers
--     pending = [number],      number of pending timers
--     waiting = [number]       number of unexpired timers
-- }
local sys_info = info.sys


for timer_name, timer in pairs(info.jobs) do
    local meta = timer.meta
    local elapsed_time = timer.elapsed_time
    local runs = timer.runs                     -- total number of runs
    local faults = timer.faults                 -- total number of faults (exceptions)
    local last_err_msg = timer.last_err_msg     -- the error message for last execption

    -- meta.name is an automatically generated string 
    -- that stores the location where the creation timer was created.
    -- Such as 'task.lua:56:start_background_task()'

    -- meta.callstack is an array of length three, 
    -- each of item stores a layer of callstack information.
    -- Such as:
    -- callstack[1] = {
    --     line = 56,                           timer is created on this line
    --     func = "start_background_task",      timer is created in this function
    --     source = "task.lua"                  timer is created in this file
    -- }

    -- callstack[2] = {
    --     line = 372,                          function `start_background_task` is called on this line
    --     func = "init_worker",                function `start_background_task` is called in this function
    --     source = "init.lua                   function `start_background_task` is called in this file
    -- }

    -- callstack[3] = nil                       nil mean code at C language


    -- elapsed_time is a table that stores the 
    -- maximum, minimum, average and variance 
    -- of the time spent on each run of the timer.
    -- Such as:
    -- elapsed_time = {
    --     max = 100
    --     min = 50
    --     avg = 70
    --     variance = 12
    -- }
end


```
