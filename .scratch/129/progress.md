# #129 T08 武器系统进度

基线：feature/122-content-baseline @ 73f0996，worktree 分支 feature/129-weapons。
编辑器冻结：不做任何编辑器写操作；技能预设创建/绑定列入编辑器待办（Gitea 评论 + 最终报告）。

## 失败方式清单（先列后写）

近战/空手：
- 间隔外连点打出第二击；空手残留 25 伤害（预设属性兜底）；换武器绕过冷却；
- 客户端伪造 RequestCast 直接结算伤害；命中盒射程与表不一致；
- 同一 AnchorStart 重放对同目标双扣（命中身份去重失效）。

枪械：
- 超射速连发（客户端加速/重复按键）；空匣打出负弹量；换弹中发射；
- 切枪绕过换弹或冷却；重连后射速/弹量状态串台；
- 枪口射线误伤口径（穿墙、打队友口径不符）；数值与商店表不一致。

投掷/爆炸物：
- 消耗不是恰好一件；重放重复扣；落点超 20 米未钳制；
- 落水不生成保底鱼 / 生成首领（普通投掷召唤首领）；保底鱼数量越界（<3 或 >5）；
- 爆炸半径不是 5 米；落地/落水分支搞反；Detonate 重放双扣；爆炸自伤刷屏。

持久化/接缝：
- 库存/选中/手持重进丢失（#124 契约破坏）；弹匣被误写进 #123 存档快照；
- 手持已失效武器发起攻击；伤害绕过 #128 统一入口。

## 设计定稿（勘测后）

1. **空手/近战伤害**：`server/AbilityAPI.lua` 加挥砍登记（StageSwing/TakeSwing，TTL 1.5s，
   时钟读不到时宽松处理）。MgrWeapon 攻击前按 `GameCfg.Ability` 表登记 {damage, range}，
   再 CastAbility 走现有挥砍预设（纯表现）。`melee_hit` 行为对玩家只认登记值：
   未登记不建命中盒不结算（堵伪造 RequestCast 与 25 残留）；命中盒 offset z=range/2、scale z=range。
   GM 近战加成（MgrGM:GetMeleeDamage）在行为侧叠加，登记值为基础。
2. **CastGuard 链**：AbilityAPI.AddCastGuard(fn) 追加守卫（SetCastGuard 单设语义不变，
   #128 测试兼容）；MgrWeapon 注册「近战槽必须有登记」守卫，鱼施法（非玩家单位）不受影响。
3. **枪械**：每 (userId, weaponId) 墙钟状态 {ammo, reloadUntil, fireAt}。换弹 2 秒（手动/自动同），
   到期惰性补满；切枪换不来新枪的绕过（状态按枪独立）；重开会话状态自然重置=弹匣满，
   装备/选中由 #123/#124 恢复。hitscan：PhysicsService:Raycast（角色朝向前方 GunRange 米），
   首命中分类（玩家/鱼/墙）。霰弹=同目标 5 颗独立命中身份各 20；火箭筒=直伤 500 + 落点 5 米 100。
4. **投掷**：消耗走 #123 协议（kind 'throw'，transform 恰减 1，成功回调里才发飞行物+爆炸）。
   直接投掷=朝向前方 20 米；长按选点客户端射线取点、服务端仍钳 20 米。
   FlightSec=0.8（暂取）抛物线，Update 驱动，到时 Detonate。
   水判定=MathWaterJudge（x/z 入水区）：水中先按钓表行（RodLevel==1 且 Grade=='normal'）
   权重抽 3–5 条 SpawnBlastFish，再 5 米径向伤害（结构排除首领/精英/rare）；
   陆地直接 5 米径向伤害。爆炸不伤投掷者自己。
5. **保底鱼**：MgrFishUnit 新状态 Wild + SpawnBlastFish(fishId, mult=1, position, owner)，
   Owner=投掷者（死亡→TakeKilled→Loot/Quest 复用），WildUntil=60s（暂取）到期移除，不占逃跑上限。
6. **数值集中**：全部进 `GameCfg.Ability`（Unarmed/MeleeWeapons/Guns/GunShared/Explosives/Throw），
   与 common/cfg/Shop.lua 武器页逐行核对（测试锁定）。
   暂取值（待策划确认）：火箭筒 IntervalSec=2.0、GunShared.Range=30、FlightSec=0.8、
   FishTtlSec=60、LongPressSec=0.35、ArcHeight=3。
7. **客户端**：1 号位攻击键改 WeaponAction{action='attack'}，Auto 枪按住连发（按表间隔）；
   武器键点按=手持/攻击（沿用 #124 两步）、长按=换弹；2 号位选中爆炸物时变「投掷」，
   点按=直接 20 米、长按=选点（ScreenPointToRay+射线，WorldToViewportPoint 标记）。
   手势状态机抽成 client/PressGesture.lua（纯模块可测）；回包 WeaponResult 提示换弹/空匣。

## 提交计划（小步）

1. tests + GameCfg.Ability 数值（红→绿）
2. AbilityAPI 挥砍登记 + AddCastGuard（红→绿）
3. melee_hit 登记驱动 + combat_behavior_test 改（红→绿）
4. MgrWeapon 空手/近战/枪械/换弹（红→绿）
5. MgrWeapon 投掷/爆炸 + 存档协议（红→绿）
6. MgrFishUnit Wild 保底鱼（红→绿）
7. main.lua 注册+接线（含源码接线守卫测试）
8. client PressGesture + LocalAttackButton + ScreenMain（红→绿）
9. 全量 fast/full + loadfile + 双轴 review + Gitea 评论

## 当前状态

- [x] 勘测与设计定稿
- [ ] 各提交项（随完成勾选）
