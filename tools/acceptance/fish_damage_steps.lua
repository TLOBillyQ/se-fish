local DamageNotice = require('common.DamageNotice')
local DamageFloat = require('client.DamageFloat')

return { patterns = {
    { '^鱼当前生命值为 ([%d%.]+)$', function(world, before)
        world.before = tonumber(before)
    end },
    { '^鱼服务端生命值变为 ([%d%.]+)$', function(world, after)
        world.after = tonumber(after)
        world.payload = DamageNotice.FromHealth(7, world.before, world.after, { x = 1, y = 2, z = 3 })
    end },
    { '^伤害跳字显示 (%d+)$', function(world, displayed)
        assert(world.payload and DamageFloat.DisplayAmount(world.payload.amount) == tonumber(displayed))
        assert(world.after == world.before - world.payload.amount)
    end },
    { '^不发送伤害跳字通知$', function(world)
        assert(world.payload == nil)
    end },
} }
