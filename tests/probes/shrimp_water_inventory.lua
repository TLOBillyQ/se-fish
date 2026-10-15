-- #102 只读核查水面预设根与附带子件，防止整套鱼塘预设误当纯水面。
local world = editor:GetService('World')
for _, name in ipairs({ 'Z2_Water', 'Z3_Water' }) do
    local root = assert(world:FindFirstChild(name))
    for _, key in ipairs({ 'RenderMeshId', 'PhysicsMeshId', 'CanCollide', 'Size', 'AssetId' }) do
        print('SHRIMPWATER102|' .. name .. '|' .. key .. '=' .. tostring(root:GetProperty(key)))
    end
    local children = root:GetChildren()
    print('SHRIMPWATER102|' .. name .. '|children=' .. #children)
    for _, child in ipairs(children) do
        print('SHRIMPWATER102|' .. name .. '|child=' .. tostring(child.Name) .. '|type=' .. tostring(child:GetUnitType()))
    end
end
return 'SHRIMPWATER102 done'
