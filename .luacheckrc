stds.busted = {
    read_globals = {
        "insulate", 
        "it", 
        "setup",
        "lazy_setup",
        "teardown",
        "lazy_teardown",
        "before_each",
        "after_each",
        "randomize",
        assert = {
            fields = {
                "is_true",
                "is_false",
                "same",
                "near",
                has = {
                    fields = { "errors" }
                },
                has_no = {
                    fields = { "errors" }
                }
            }
        }}
}

stds.resty = {
    read_globals = {
        ngx = {
            fields = {
                "sleep",
                "log",
                "ERR",
                "update_time",
                "now",
                worker = {
                    fields = {
                        "exiting"
                    }
                },
                timer = {
                    fields = {
                        "running_count",
                        "at",
                        "every"
                    }
                }
            }
        }
    }
}

files["spec/*.lua"].std = "+busted+resty"
files["spec/*.lua"].ignore = {"212"}

files["lib/**/*.lua"].std = "+resty"
files["lib/**/*.lua"].ignore = {"212"}