-- #131 T10 生存恢复：濒死、免费虚弱复活与离线恢复（server/Mgr/MgrSurvival.lua + MgrVitals 接管）。
-- 数值来源：策划案--渔力全开.docx 濒死/复活段（15 秒抢救、30 秒倒计时、10% 血、虚弱 1 分钟半速、
-- 肾上腺素恢复 10%）与物品表 item171；验收清单见 issue #131。
-- 失败方式（先列后写）：
--   1. 致命伤害不锁 1 血直接死亡，或锁血后濒死中还能被扣血（连续攻击越过濒死）；
--   2. 濒死 15 秒不到就转死亡 / 到了不转；死亡 30 秒不到就复活 / 到了不复活；虚弱 60 秒提前结束；
--   3. 虚弱复活血量不是 10%（30）、饥饿低于 30、没进虚弱、虚弱没半速、结束没恢复；
--   4. 濒死/死亡中饥饿照走、能吃、能抛竿（CanAct 失守）；濒死不断钓鱼、不放举着的鱼；
--   5. 肾上腺素：非濒死也能用、没物品也复活、并发双击多扣、消耗成功不复活；
--   6. 离线：濒死/死亡退出重进不是 10% 血加虚弱；虚弱退出剩余时间不对；旧回调覆盖新状态；
--   7. 原生 Died/Reborn 与轮询兜底同时触发时重复复活；MgrVitals 兜底 Reborn 在接管期抢跑；
--   8. 抢救接缝：非濒死能救、救后血量不是 10%；状态泄漏到其他玩家；离开后状态残留。
local lu = require('luaunit')

TestSurvivalConfig = {}

function TestSurvivalConfig:test_values_match_design_doc()
    local cfg = require('common.GameCfg').Survival
    lu.assertNotNil(cfg)
    lu.assertEquals(cfg.DownedSec, 15)             -- 策划案：十五秒之内可以抢救
    lu.assertEquals(cfg.DeadSec, 30)               -- 策划案：30 秒倒计时结束虚弱复活
    lu.assertEquals(cfg.ReviveHealthPercent, 10)   -- 策划案：复活血量 10%
    lu.assertEquals(cfg.ReviveHungerPercent, 10)   -- 验收：无付费复活饥饿至少 30（300×10%）
    lu.assertEquals(cfg.WeakSec, 60)               -- 策划案：虚弱持续 1 分钟
    lu.assertEquals(cfg.WeakSpeedScale, 0.5)       -- 策划案：移动速度下降 50%
    lu.assertEquals(cfg.AdrenalineItemId, 'item171') -- 物品表 R172 肾上腺素（自救道具）
end
