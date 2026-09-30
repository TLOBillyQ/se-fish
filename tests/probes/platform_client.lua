-- #147 客户端 UI 与真实 RE 回包取证；server platform_runtime.lua 完成后执行。
-- editor-cli exec -p client --file <本文件绝对路径> --json。
local screen = require('client.ScreenHandlers.ScreenBlindbox')
local platform = require('client.ScreenHandlers.ScreenPlatform')
local survival = require('client.ScreenHandlers.ScreenSurvival')
local world = game:GetService('World')
local tag = 'C147-' .. tostring(math.floor(world:GetServerTime()))
local function log(...) print('PLATFORM147', tag, ...) end
screen:SetOpen(true)
log('盲盒入口', tostring(screen.Panel ~= nil), 'pity=' .. tostring(screen.Pity))
log('盲盒结果', screen.Nodes.LabelBlindboxResult and screen.Nodes.LabelBlindboxResult.Text or '无节点')
log('保底文案', screen.Nodes.LabelBlindboxPity and screen.Nodes.LabelBlindboxPity.Text or '无节点')
log('单抽价格', screen.Nodes.BtnBlindboxSingleText and screen.Nodes.BtnBlindboxSingleText.Text or '无节点')
log('十连价格', screen.Nodes.BtnBlindboxTenText and screen.Nodes.BtnBlindboxTenText.Text or '无节点')
log('测试驱动已收起', tostring(platform.Nodes.PlatformTestDriver and not platform.Nodes.PlatformTestDriver.Visible))
log('复活UI', tostring(survival.AdReviveBtn ~= nil), tostring(survival.PaidReviveBtn ~= nil))
log('DONE 客户端回包与节点取证')
