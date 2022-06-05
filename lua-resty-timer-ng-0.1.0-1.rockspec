package = "lua-resty-timer-ng"
version = "0.1.0-1"
source = {
   url = "git://github.com/kong/lua-resty-timer-ng",
   branch = "master"
}
description = {
   summary = "A scalable timer library for OpenResty.",
   license = "Apache 2.0",
   homepage = "https://github.com/kong/lua-resty-timer"
}
dependencies = {

}
build = {
   type = "builtin",
   modules = {
     ["resty.timer-ng"] = "lib/resty/timer-ng/init.lua",
     ["resty.timer-ng.job"] = "lib/resty/timer-ng/job.lua",
     ["resty.timer-ng.array"] = "lib/resty/timer-ng/array.lua",
     ["resty.timer-ng.constants"] = "lib/resty/timer-ng/constants.lua",
     ["resty.timer-ng.utils"] = "lib/resty/timer-ng/utils.lua",

     ["resty.timer-ng.wheel"] = "lib/resty/timer-ng/wheel/init.lua",
     ["resty.timer-ng.wheel.group"] = "lib/resty/timer-ng/wheel/group.lua",

     ["resty.timer-ng.thread.group"] = "lib/resty/timer-ng/thread/group.lua",
     ["resty.timer-ng.thread.loop"] = "lib/resty/timer-ng/thread/loop.lua",
     ["resty.timer-ng.thread.super"] = "lib/resty/timer-ng/thread/super.lua",
     ["resty.timer-ng.thread.worker"] = "lib/resty/timer-ng/thread/worker.lua",
   }
}