# #112 试玩验收记录

地图：钓鱼怎么这么危险啊喂！（SE）；编辑器 CLI 0.19.1；试玩会话 `0afa7e3`（2026-09-27）。

复跑：将 `evidence/issue112-probe.lua` 路径传给 `editor-cli exec --platform server --file <绝对路径> --json`。在试玩开始且 `editor-cli status --json` 显示 `in_game_runtime=true` 后执行。探针暂时将 `WaterCircle2` 的抽鱼表换成空表，到达上钩时间后恢复原表并重抛；探针用真实玩家数据、真正的抛竿管理器和真实鱼饵快照，角色转向并移到水域边。使用 `editor-cli log grep 'PROBE112|\[MgrCast\]|\[ScreenMain\]' --play-session 0afa7e3 --json` 回看。

本次复测关键日志（服务端与客户端同轮）：

```text
[18:39:18.280] [client] [ScreenMain] 已入水，等待上钩 4 WaterCircle2
[18:39:18.293] [server] PROBE112 CAST true before=4 after=3
[18:39:21.269] [client] [ScreenMain] 抛竿失败 noFish 本次没有鱼上钩，请重新抛竿
[18:39:21.270] [server] [MgrCast] 空抽 aU5A95JB9rit0DUl WaterCircle2
[18:39:21.773] [server] PROBE112 EMPTY true bait=3
[18:39:23.828] [client] [ScreenMain] 已入水，等待上钩 5 WaterCircle2
[18:39:23.832] [server] PROBE112 RECAST true bait=2
[18:39:26.828] [server] [MgrCast] 上钩 aU5A95JB9rit0DUl catfish 1.15
[18:39:27.344] [server] PROBE112 HOOK hooked catfish
```

`editor-cli log trace --play-session 0afa7e3 --json`：0 错误、0 警告。`evidence/issue112-empty.png` 与 `evidence/issue112-prompt.png` 是该地图空抽过程取得的有效游戏帧；CLI 返回截图尺寸与有效性，但未提供截图内文字识别或逐帧状态，不能以此独立认定提示和浮漂清理画面均可见。提示文字由客户端日志确认，浮漂与等待文字的生命周期由 `tests/gameplay/reel_ui_test.lua` 验证；视觉验收尚需人工核对截图及前后画面。第二轮会话 `00c227b` 中 18:43:13.279 再次出现 noFish 客户端日志，18:43:15.805 再次重抛成功，18:43:19.328 上钩 bass。
