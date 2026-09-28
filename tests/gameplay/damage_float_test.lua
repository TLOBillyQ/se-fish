local lu = require('luaunit')
local DamageNotice = require('common.DamageNotice')
local GameCfg = require('common.GameCfg')
local DamageFloat = require('client.DamageFloat')

TestDamageNotice = {}

function TestDamageNotice:test_rounding_and_effective_health()
    local pos = { x = 3, y = 4, z = 5 }
    for _, case in ipairs({ { 10, 7.3, 3 }, { 10, 7.6, 2 },
        { 10, 9.5, 1 }, { 10, 9.9, 1 }, { 4, 0, 4 } }) do
        local payload = DamageNotice.FromHealth(42, case[1], case[2], pos)
        lu.assertEquals(DamageFloat.DisplayAmount(payload.amount), case[3])
        lu.assertEquals(payload.targetId, 42)
        lu.assertEquals(payload.position.y, 4)
    end
    lu.assertNil(DamageNotice.FromHealth(42, 4, 4, pos))
    lu.assertNil(DamageNotice.FromHealth(42, 4, 5, pos))
end

TestDamageFloat = {}

function TestDamageFloat:test_offscreen_and_reuse_reset()
    local saved = { game = _G.game, Vector2 = _G.Vector2, Vector3 = _G.Vector3, Color = _G.Color }
    local time, visible = 0, false
    local created = {}
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
    _G.game = { GetService = function(_, name)
        if name == 'CameraService' then return { MainCamera = {}, WorldToViewportPoint = function(_, point)
            lu.assertEquals(point.y, 5 + GameCfg.DamageFloat.HeadHeight)
            return { x = 100, y = 200, z = 2 }, visible
        end } end
        if name == 'World' then return {
            GetServerTime = function() return time end,
            CreateUnit = function(_, _, spec)
                local node = { Parent = spec.Parent, Destroy = function(self) self.Destroyed = true end }
                created[#created + 1] = node
                return node
            end,
        } end
    end }
    local ok, err = pcall(function()
        DamageFloat:Bind({}, { x = 800, y = 600 })
        local payload = { targetType = 'fish', targetId = 7, amount = 0.5,
            position = { x = 3, y = 5, z = 9 } }
        DamageFloat:Show(payload)
        lu.assertEquals(#created, 0)
        visible = true
        DamageFloat:Show(payload)
        lu.assertEquals(created[1].Text, '1')
        lu.assertEquals(created[1].Position.y, 400)
        DamageFloat:Show(payload)
        lu.assertEquals(#created, 2)
        lu.assertNotEquals(created[1].Position.x, created[2].Position.x)
        visible = false
        time = 0.5
        DamageFloat:Update()
        lu.assertFalse(DamageFloat.Active[1].Node.Visible)
        visible = true
        DamageFloat:Update()
        lu.assertTrue(DamageFloat.Active[1].Node.Visible)
        time = 1.1
        DamageFloat:Update()
        lu.assertEquals(#DamageFloat.Pool, 2)
        payload.amount, payload.critical = 10, true
        DamageFloat:Show(payload)
        lu.assertEquals(#created, 2)
        lu.assertEquals(DamageFloat.Active[1].Node.Text, '10')
        lu.assertEquals(DamageFloat.Active[1].Node.FontSize, GameCfg.DamageFloat.CriticalFontSize)
        lu.assertEquals(DamageFloat.Active[1].Node.Opacity, 1)
        DamageFloat:Clear()
        lu.assertEquals(#DamageFloat.Active, 0)
        lu.assertTrue(created[1].Destroyed and created[2].Destroyed)
    end)
    DamageFloat:Clear()
    for key, value in pairs(saved) do _G[key] = value end
    if not ok then error(err) end
end
