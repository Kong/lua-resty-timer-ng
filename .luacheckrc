files["spec/*.lua"].std = "+busted+ngx_lua"
files["spec/*.lua"].ignore = {"212", "111"}

files["lib/**/*.lua"].std = "+ngx_lua"
files["lib/**/*.lua"].ignore = {"212", "111"}
files["lib/**/*.lua"].max_line_length = 80