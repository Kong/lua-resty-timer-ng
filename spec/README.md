# Test Suites

The unit tests for this library are run by `busted` and `resty`.

## Run Tests

Pre-requirements

```shell
luarocks install busted
luarocks install busted-htest
luarocks install luacov
luarocks install luacov-console
```

Run the following command to run some tests.

```shell
resty   -c 1024 \
        --http-conf "lua_max_running_timers 1024;" \
        --http-conf "lua_max_pending_timers 1024;" \
        -I lib \
        -I spec \
        --errlog-level debug \
        spec/runner.lua --coverage --verbose -o htest spec/
# or
resty   -c 1024 \
        --http-conf "lua_max_running_timers 1024;" \
        --http-conf "lua_max_pending_timers 1024;" \
        -I lib  \
        -I spec \
        spec/runner.lua --coverage --verbose -o htest spec/
```

Run the following command to generate a coverage report.

```shell
luacov lib/resty/timerng
luacov-console lib/resty/timerng

# summary
luacov-console -s

# details of lib/resty/timer/init.lua
luacov-console -l lib/resty/timerng/init.lua
```

## Environment Variables

### `TIMER_SPEC_TEST_ROUND`

It is used to control the rounds of  
`spec/02-once_spec.lua` and `spec/03-every_spec.lua`.
The more rounds, the more cases are covered.

Generally, you do not need to change it 
unless you are concerned about the error in the time calculation 
and increasing it allows you to check the accumulation of errors.