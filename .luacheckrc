-- luacheck: what the code is held to (underroot's settings). Undefined and
-- stray globals, unused locals and values; not line length, unused arguments,
-- shadowing or empty branches kept for their comment.
std = "luajit"
globals = { "love" }
ignore = { "631", "212", "411", "421", "431", "542" }
exclude_files = { "lib/" }
