-- 三轴独立同权重；恰好两同按实际投入价值返金币，三同优先，仅给对应大奖。
return {
    Axes = 3,
    PairRule = 'exactlyTwo',
    TripleRule = 'tripleFirst',
    Patterns = {
        { number = 1, name = '鳄雀鳝', weight = 22, pairMultiplier = 2, tripleReward = { kind = 'weaponChoice', choiceCount = 1, itemKeys = { 'item152', 'item153', 'item154', 'item155', 'item156' }, itemNames = { '淬毒匕首', '秘银匕首', '黄金匕首', '黑曜石匕首', '锯齿匕首' } }, implemented = false, source = '抽奖表!R3' },
        { number = 2, name = '小白龙', weight = 20, pairMultiplier = 3, tripleReward = { kind = 'weaponChoice', choiceCount = 1, itemKeys = { 'item157', 'item158', 'item159', 'item160', 'item161' }, itemNames = { '银斧', '金斧', '炽焰战斧', '血吼', '无坚不摧之力' } }, implemented = false, source = '抽奖表!R4' },
        { number = 3, name = '蟹老板', weight = 18, pairMultiplier = 5, tripleReward = { kind = 'weaponChoice', choiceCount = 1, itemKeys = { 'item162', 'item163', 'item164', 'item165', 'item166' }, itemNames = { '沙漠之鹰', '霜之新星', '雷霆之力', '黄金AK47', '连发火箭筒' } }, implemented = false, source = '抽奖表!R5' },
        { number = 4, name = '三头鲨', weight = 16, pairMultiplier = 7, tripleReward = { kind = 'item', itemName = '加速药水', itemKey = 'item167' }, implemented = false, source = '抽奖表!R6' },
        { number = 5, name = '虎鲸', weight = 14, pairMultiplier = 10, tripleReward = { kind = 'item', itemName = '变大药水', itemKey = 'item168' }, implemented = false, source = '抽奖表!R7' },
        { number = 6, name = '风神翼龙', weight = 5, pairMultiplier = 15, tripleReward = { kind = 'item', itemName = '风神之翼', itemKey = 'item169' }, implemented = false, source = '抽奖表!R8' },
        { number = 7, name = '哥斯拉', weight = 5, pairMultiplier = 20, tripleReward = { kind = 'item', itemName = '哥斯拉', itemKey = 'item170' }, implemented = false, source = '抽奖表!R9' },
    },
}
