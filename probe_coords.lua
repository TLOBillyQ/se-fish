local physics = game:GetService("PhysicsService")
local function probe(label, x, z)
    local params = RaycastParams.New()
    local ok, hit = pcall(physics.Raycast, physics,
        Vector3.New(x, 20, z), Vector3.New(0, -30, 0), params)
    if ok and hit and hit.Position then
        print("PROBE " .. label .. " x=" .. x .. " z=" .. z ..
              " y=" .. string.format("%.4f", hit.Position.y) ..
              " ny=" .. string.format("%.4f", hit.Normal and hit.Normal.y or -1))
    else
        print("PROBE " .. label .. " x=" .. x .. " z=" .. z .. " MISS")
    end
end
-- worm-3 候选：朝 +x 方向山体
probe("w3a", -3.75, 27.75)
probe("w3b", -2.75, 27.75)
probe("w3c", -1.75, 27.75)
-- worm-4 候选：z=17.75 一带找 y=5.0
probe("w4a", -3.75, 17.75)
probe("w4b", -2.75, 17.75)
probe("w4c", -1.75, 17.75)
probe("w4d", -4.75, 17.75)
probe("w4e", -0.75, 17.75)
