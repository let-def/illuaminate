local foo = "123\a\b\t\x23"
local bar = [=[
foo
]=]

local a = { 0, 0x1, -0x1, - 0x1 , - 0.0, -.0e2 }

function a:f() end

a.y.z = a:f()

-- Line comment
--[[ Block comment ]]

--[=[
Multi-line
block
comment
]=]
