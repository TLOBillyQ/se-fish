-- #65 P2：配置锚点基线探针的同步守卫（fast 车道）。
-- tests/probes/config_anchor_resolution.lua 的数据块由 tools/gen_config_anchor_probe.lua 生成：
-- 编辑器 exec 沙盒里 require 不可用（sdk.common.lua:830）、也没有 io，探针无法自己加载
-- common/GameCfg.lua，只能嵌字面量。本用例保证这份字面量不随配置漂移——配置改了锚点名却忘了
-- 重新生成，就会在这里红。
local gen = require('tools.gen_config_anchor_probe')
local GameCfg = require('common.GameCfg')

describe('#65 P2 配置锚点基线', function()
    it('探针数据块与当前 GameCfg 逐字节一致', function()
        local text = gen.readProbe()
        assert.is_truthy(text, '读不到探针文件 ' .. gen.PROBE)
        local entries, labels = gen.collect(GameCfg)
        local want = gen.renderBlock(entries, labels)
        local got = gen.extractBlock(text)
        assert.is_truthy(got, '探针缺少生成标记 ' .. gen.BEGIN_MARK)
        assert.are.equal(want, got, '数据块已漂移：请运行 lua tools/gen_config_anchor_probe.lua')
    end)

    it('清单覆盖七区且每条都带来源与预期区', function()
        local entries, labels = gen.collect(GameCfg)
        assert.are.equal(7, #labels)
        assert.is_true(#entries > 0)
        for _, entry in ipairs(entries) do
            assert.is_truthy(entry.source ~= '' and entry.zone ~= '-' and entry.name ~= '')
        end
    end)
end)
