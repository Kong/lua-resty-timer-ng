# lua-resty-timer-ng

A scalable timer library for OpenResty.

- [lua-resty-timer-ng](#lua-resty-timer-ng)
  - [Status](#status)
  - [Synopsis](#synopsis)
  - [Description](#description)
  - [Statistics](#statistics)
  - [History](#history)
  - [Methods](#methods)
    - [new](#new)
    - [start](#start)
    - [freeze](#freeze)
    - [once](#once)
    - [every](#every)
    - [run](#run)
    - [pause](#pause)
    - [cancel](#cancel)
    - [destroy](#destroy)
    - [is_managed](#is_managed)
    - [stats](#stats)

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
            wheel_setting = {
                level = 4,
                slots = { 10, 60, 60, 24 },
            },
            resolution = 0.1,
            threads = 10,
            restart_thread_after_runs = 50,
        }
        timer_sys = timer_module.new(options)

        -- ‘premature’ is used to be compatible with existing callback functions and it is always false.
        local function callback_once(premature, ...)
            -- do something
            ngx.log(ngx.ERR, "in timer example-once")
        end

        local function callback_every(premature, ...)
            -- do something
            ngx.log(ngx.ERR, "in timer example-every")
        end

        -- run after 100 ms
        local name, err = timer_sys:once("example-once", 0.1, callback_once)

        if not name then
            ngx.log(ngx.ERR, err)
        end

        -- run every 1s
        name , err = timer_sys:every("example-every", 1, callback_every)

        if not name then
            ngx.log(ngx.ERR, err)
        end
    }
}
```

## Description

This system is based on the timer wheel algorithm.
which uses the small number of timers 
created by OpenResty API `ngx.timer.at` to manage a large number of timed tasks.

In other words, it can reduce the number of fake requests.

* Efficiently, create, pause, start and cancel a timer takes O(1) time.
* Concurrency control, you can limit the number of threads.
* Easy to debug
    * Get statistics such as maximum, minimum, average, and variance of the runtime for each timer.
    * Some information that is useful for debugging, such as where the timer was created and the call stack at that time.

## Statistics

The system records the following information:

* The maximum, minimum, average, and variance of the running time of each timer.
* The location of each timer created, such as call stack.


## History

Versioning is strictly based on [Semantic Versioning](https://semver.org/)

## Methods

### new

**syntax**: *timer, err = require("resty.timer").new(options?)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

**TODO**

For example

```lua
local timer_module = require("resty.timer")
local timer_sys = timer_module.new({
    -- number of threads
    threads = 10,

    -- restart the LWP after it has run restart_thread_after_runs tasks.
    restart_thread_after_runs = 50
})
```

### start

**syntax**: *ok, err = timer:start()*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Start the timer system.

### freeze

**syntax**: *timer:freeze()*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Suspend the timer system and the expiration of each timer will be frozen.

### once

**syntax**: *name_or_false, err = timer:once(name, delay, callback, ...)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Create a once timer. You must call this method after you have called `timer:start()`.
If you have called `timer:pause()`, you must call this function after you have called `timer:start()`.

* name: The name of this timer, or if it is set to `nil`, a random name will be generated.
* callback: A callback function will be called when this timer expired, `function callback(premature, ...)`.
* delay: The expiration of this timer.


### every

**syntax**: *name_or_false, err = timer:every(name, interval, callback, ...)*

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


### destroy

**syntax**: *timer:destroy()*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

**TODO**

### is_managed

**syntax**: *timer:is_managed(name)*

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**

Return `true` if the specified timer is managed by this system, and `false` otherwise.

* `name`: name of timer

### stats

**syntax**: info, err = timer:stats(verbose?)

**context**: *init_worker_by_lua\*, set_by_lua\*, rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, header_filter_by_lua\*, body_filter_by_lua\*, log_by_lua\*, ngx.timer.\**


Get the statistics of the system.

* `verbose`: If true, the statistics for each timer will be returned.

For example:

```lua
local info, err = timer:stats(true)

if not info then
    -- error
end

-- info.sys = {
--     running = [number],      number of running timers
--     pending = [number],      number of pending timers
--     waiting = [number],      number of unexpired timers
--     total   = [number],      running + pending + waiting
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
