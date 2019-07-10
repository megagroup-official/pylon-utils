package = "pylon-utils"
version = "1.0"

source = {
  url = "git://github.com/megagroup-official/pylon-utils",
  tag = "1.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Useful functions for Lua/LuaJIT",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["pylon.utils"] = "pylon/utils.lua"
  }
}