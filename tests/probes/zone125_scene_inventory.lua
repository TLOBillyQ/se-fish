-- #125 编辑器只读盘点探针：editor-cli exec --file <本文件> --expect-edit-mode --json。
-- 全量 GetDescendants 当前触发 SDK 反射错误，只读取下列已确认可枚举的类型。
-- 返回 Name|x,y,z，以分号分隔；转换为 {Name, Position={x,y,z}} 后交给 MathWaterJudge.InspectScene。
-- 单位名与坐标匹配只供诊断，不能证明保存、碰撞、刷新或边界验收通过。
local world = editor:GetService('World')
local rows = {}
for _, unitType in ipairs({ 'WorldUnit', 'SpawnLocationUnit', 'TriggerUnit' }) do
    for _, unit in ipairs(world:GetUnitsByUnitType(unitType, true)) do
        local p = unit.Position -- 编辑器 SDK 返回数组；运行时 Vector3 才使用 x/y/z。
        rows[#rows + 1] = unit.Name .. '|' .. tostring(p[1]) .. ',' .. tostring(p[2]) .. ',' .. tostring(p[3])
    end
end
return table.concat(rows, ';')
