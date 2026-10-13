-- 离线属性边界：真实业务/根门面/vendor，仅引擎单位与World替身。
local M = {}
function M.New(playerData, multiplier)
    local cache, all, prepared = {}, {}, {}
    local function prepare(unit, prefab)
        unit.attrs = unit.attrs or {}
        unit.GetAttribute = unit.GetAttribute or function(self,k)return self.attrs[k]end
        unit.SetAttribute = unit.SetAttribute or function(self,k,v)self.attrs[k]=v end
        if not prepared[unit] then
            prepared[unit] = true
            local original = unit.GetChildren
            unit.GetChildren = function(self)
                local children, seen = {}, {}
                for _, child in ipairs(original and original(self) or {}) do
                    children[#children + 1], seen[child] = child, true
                end
                for _, child in ipairs(all) do
                    if child.Parent == self and not seen[child] then children[#children + 1] = child end
                end
                return children
            end
        end
        unit.IsA = unit.IsA or function()return true end
        unit.FindFirstChildOfClass = unit.FindFirstChildOfClass or function(_,kind)
            if prefab and kind=='PresetLink' then return {GetAttribute=function()return prefab end} end
        end
        unit.Destroy = unit.Destroy or function(self)self.Parent=nil self.destroyed=true end
        return unit
    end
    local world={CreateAsset=function()
        local unit=prepare({},'AttrUnit') all[#all+1]=unit return{unit}
    end}
    local env=setmetatable({game={GetService=function()return world end},Vector3={New=function(x,y,z)return{x=x,y=y,z=z}end}}, {__index=_G})
    env.require=function(name)
        if cache[name]then return cache[name]end
        cache[name]=assert(loadfile(name:gsub('%.','/')..'.lua','t',env))() return cache[name]
    end
    local mgr=env.require('server.Mgr.MgrAttr')
    mgr.PlayerData=playerData mgr.MoveMultiplierProvider=multiplier
    local state=mgr.State
    function mgr:State(player)
        if player.Character then prepare(player.Character) end
        return state(self,player)
    end
    return mgr
end
return M
