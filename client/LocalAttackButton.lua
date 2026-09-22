-- 攻击按钮：道具按钮的最小形态——手持物决定道具按钮的行为（吃、抛竿、挥砍……，见 CONTEXT.md「道具栏」）。
-- 物品/手持体系尚未落地（issue #6 列为后续），本模块先把「手持武器 → 按钮行为 = 挥砍」这条验证链路跑通：
-- 点按钮 = 经客户端聚合入口请求施放挥砍技能，权威判定在服务端（包内 RemoteEvent 通道）。
local Players = game:GetService("Players")
local World = game:GetService("World")

local GameCfg = require("common.GameCfg")
local AbilityAPI = require("client.AbilityAPI")

local LocalAttackButton = {}

local BUTTON_SIZE = Vector2.New(180, 180)
-- 设备分辨率像素、节点中心定位、左下原点；右下角是原生按钮区，放右缘中部避开
local BUTTON_MARGIN = Vector2.New(220, 900)

-- 挥砍技能槽位由配置决定（手持物体系落地后改由手持物反查）
local function findMeleeSlot()
    for _, entry in ipairs(GameCfg.Ability.InitialAbilities or {}) do
        if entry.AnchorBehavior == "melee_hit" then
            return entry.Index
        end
    end
    return nil
end

function LocalAttackButton:Start()
    -- 幂等：重复启动不叠加按钮与监听
    if self.BtnAttack then
        return
    end
    local slot = findMeleeSlot()
    if not slot then
        print("[LocalAttackButton] 配置里没有挥砍技能（AnchorBehavior=melee_hit），不建按钮")
        return
    end
    self.Slot = slot

    local euiMgr = _G.GameUI:GetEuiManager()
    if not euiMgr then
        print("[LocalAttackButton] EuiManager 未就绪")
        return
    end
    local resolution = euiMgr:GetDeviceResolution()

    local btn = World:CreateUnit("EUIButton", {
        Parent = euiMgr:GetRootNode(),
        Name = "BtnAttack",
        Position = Vector2.New(resolution.x - BUTTON_MARGIN.x, BUTTON_MARGIN.y),
        Size = BUTTON_SIZE,
    })
    -- 运行时建的按钮 TouchEnabled 默认 false，要点得动先置 true
    btn.TouchEnabled = true
    btn.ButtonText = "攻击"
    btn.ButtonTextColor = Color.New(255, 255, 255, 255)
    btn.ButtonNormalColor = Color.New(220, 60, 60, 255)
    self.BtnAttack = btn

    self.ClickConn = btn.OnClicked:Connect(function()
        self:RequestMelee()
    end)
end

-- 按钮背后的处理函数（探针可直接调用取证；按钮点击不走 input touch，见 eggy-lua 试玩参考）
function LocalAttackButton:RequestMelee()
    if not self.Slot then
        return
    end
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local manager = character and AbilityAPI.GetManagerForUnit(character)
    if not manager then
        print("[LocalAttackButton] 技能管理器未就绪，忽略本次点击")
        return
    end
    print("[LocalAttackButton] 请求挥砍 slot=" .. tostring(self.Slot))
    AbilityAPI.RequestCast(manager, self.Slot)
end

return LocalAttackButton
