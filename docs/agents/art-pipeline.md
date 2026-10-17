# 美术资产流水线

为地图产出鱼类等模型与动画时读本文。尺寸口径见 [ADR-0004](../adr/0004-fish-asset-scale.md)。

## 定位

本仓只管**接入方式与约定**：流水线用哪两个 MCP server、装什么版本、导出怎么命名与分件、验收看什么。**资产本体不进本仓**——正式资产走编辑器导入，预设随地图存档（见 [官方包接入参考](../packages-reference.md)）。生成某个模型的具体过程不在此记录。

## 接入

需要两个 MCP server：`blender`（驱动 Blender 本体）与 `meshy`（AI 生成模型）。

### blender —— Blender 官方 MCP 插件 + `blmcp`

两侧都要：

- **Blender 侧**：Blender **≥ 5.1.0**，装官方 **MCP** 插件（Blender Lab，`id=mcp`，已验证 **1.0.3**）。插件注册 `blmcp.server_start` / `blmcp.server_stop`，默认监听 `localhost:9876`，null 字节分隔 JSON 协议；打开 Auto Start 后随 Blender 启动。插件是上游产物、随 Blender 分发，不必入库（Windows 下装在 `%APPDATA%\Blender Foundation\Blender\<版本>\extensions\`，可据此核对已装版本）。
- **Server 侧**：pip 包 `blender-mcp`（顶层模块 `blmcp`，入口 `blender-mcp`），已验证 **1.0.2**，来源 `https://projects.blender.org/lab/blender_mcp.git`。装完后 `blender-mcp` 在 Python 的 `Scripts` 目录，**通常不在 PATH 上**，配置里按需写绝对路径。

工具以 `mcp__blender__*` 注册，常用的有 `execute_blender_code`（在已连接的 Blender 里执行 Python）、`get_objects_summary`、`get_blendfile_summary_*`、`search_api_docs` / `search_manual_docs`（随包带全量 Blender API 与手册，可直接检索）、`render_viewport_to_path`、`get_screenshot_of_window_as_image`。

> 别照搬社区版 blender-mcp 的工具名：`get_scene_info`、`get_viewport_screenshot` **不存在**。

### meshy

`npx -y @meshy-ai/meshy-mcp-server`，凭据走环境变量 **`MESHY_API_KEY`**。

**密钥永不入库。** 仓库内引用与本地配置一切写 `MESHY_API_KEY` 变量名，值只放在本机环境（用户级环境变量）。

> 本机实测：Meshy 的 MCP 通道在 Node/undici 下连 `api.meshy.ai` 会 TLS 断开（`--use-system-ca` 可绕，但不可靠）。试点改走 REST 直连同一环境的 `MESHY_API_KEY`，脚本与参数一并留痕，见下方「试点复盘」。

### 前端配置

仓库不提交 MCP 配置，也不再维护 DSH 接入。在所用前端（目前是 Codex）里接入 `blender` 与 `meshy` 两个 MCP server，`meshy` 的 key 走环境变量 `MESHY_API_KEY`；接入后核对工具已注册。

## 制作约定

- 建模前先定尺度：按 [ADR-0004](../adr/0004-fish-asset-scale.md) 的单位方块口径做，别在游戏对象上补缩放。
- 模型与动画分件导出，贴图按 ADR-0004 的编码约定。
- 蒙皮导入器可能拒绝 UCX 碰撞网格。碰撞体在游戏引擎侧搭，Blender 里的碰撞代理只作编辑参考，不随导出交付。
- 导出的对照文件与验收数据放在美术工作区，**不进本仓**。
- 面数与贴图预算：单鱼不超过罗非鱼的 8268 三角面、1 个材质、1K 贴图（这是已做成的参照值，不是引擎限制，后续按实机表现再调）。
- 过程留痕：每条鱼的 Blender Python 脚本、Meshy 任务 ID 与参数存在美术工作区该鱼目录下（脚本 + `NOTES.md`），本仓文档只引用，不复制。

## 验收

1. 逐文件重导入量尺寸、核对网格数与骨骼数、确认动画帧区间。
2. 在游戏场景内按 [ADR-0004](../adr/0004-fish-asset-scale.md)「验收」一节，放到单位方块旁与参考鱼比对。
3. 播放动画后尺寸保持稳定，碰撞体同比例。

第 1 步只证明导出链路自洽；**不完成第 2 步不得宣布资产可用**。

第 1 步里的重导入量测已脚本化：报告落在美术工作区该鱼目录的 `validation/` 下，由 `art` 车道的 Gherkin（`features/art/`，读 `validation/validation.json` 断言）复核。报告不存在时验收直接失败——验收跑不起来正好等于「没做重导入校验」。美术资产根目录可用 `EGGY_ART_ASSETS` 覆盖；换机器没带美术工作区时这条车道会失败，这是有意的，别把它的绿色当成资产可用。

## 试点复盘（鲤鱼，2026-10-16）

过程数据、任务 ID、脚本与校验报告都在美术工作区 `Desktop/dev/eggy/美术资产/鲤鱼/`（脚本工具 `blend.py` 直连 Blender、`meshy.py` 走 Meshy REST，位于同级的 `Desktop/dev/eggy/tools/`）。这里只留可复用的结论。

- **额度口径要按模型档位算**：`meshy-7.1` 的预览是 **20** 额度（低模档才是 5），精修 10。一条鱼实扣 **30**；开工前按 20 报预览价。
- **精修只回 BaseColor**：Normal 与 ORM 必须在 Blender 自烘（high-poly → low-poly，roughness 值对齐参照鱼的 ORM G 通道均值）。
- **蒙皮别用 `ARMATURE_AUTO`**：本机对整条鱼求解失败（`Bone Heat Weighting: failed to find solution`），顶点组会全空、摆姿不形变。用参考鱼网格的顶点组做 Data Transfer。
- **动画源必须用已导出的动画 FBX**：从参考 `.blend` 里 `wm.append` 出来的 action 绑到同名骨架上位移恒 0，导出的是一堆静帧。另外 FBX 往返固定 **+1 帧**（导出按 `t=frame/fps`，导入按 `frame=t*fps+1`），导出前把区间平移回 1..N 才能与参照鱼逐段对齐；导出统一 `add_leaf_bones=False`，否则多出 `*_end` 骨骼、与参照件不同构。
- **尺度变换要排在烘焙之后**：把网格搬进骨架局部空间（`data.transform` + 零 `matrix_parent_inverse`）必须在渲染与法线烘焙之后做，提前换尺度会把烘焙打糊。
- **空动画探针要取全帧**：有些段的中间帧正好回到静止姿态，只对比首帧与中点会把真动画判成静帧。
- **Meshy 的参数探针要当心副作用**：`raw` 直发请求不受本地校验，服务端忽略未知字段，探测试验也可能真建任务。核账靠任务列表 + 余额差值。

## 已知缺口

- **游戏内导入**：罗非鱼已于 2026-10-16 由用户口头确认通过游戏内导入验证；模型、动画、尺寸各自的验证范围与碰撞体搭法**未留书面记录**，补齐前不要据此推定「带动画 FBX 导入已解决」。[技术难点识别](../技术难点识别.md) §1 仍是待做原型的表述，待记录补齐后再改。
- **导入路径须为纯 ASCII**：编辑器导入器的 `GetComponentData` 读不了含中文的路径，会报「加载fbx资源失败，资源不合法」并说文件不存在（2026-10-17 鲤鱼实测：从 `美术资产\鲤鱼\` 导入失败，复制到纯英文目录 `eggy\assets_import\carp\` 后导入成功）。导入前先把 FBX 与贴图复制到纯 ASCII 路径，不要直接从中文目录导入。
- **鲤鱼的游戏内验收（接缝 A）未做**：试点收尾时本机没有运行中的编辑器实例（`editor-cli status` 报 `NO_EDITOR_INSTANCES`），重导入校验与 `art` 车道虽然全绿，但按上面「验收」的口径**鲤鱼仍不能算可用**。执行步骤与取证要求见美术工作区的 `NOTES.md`。
- **鲤鱼模型有较多网格漏洞（2026-10-17，用户在编辑器里确认）**：具体部位与类型尚未梳理；重导入校验不检查网格封闭性，所以报告全绿也没发现。已决定**不重新生成**（Meshy 精修已实扣 30），留待后续工作，优先考虑在 Blender 里修补。修复前鲤鱼不可用，接缝 A 其余项（尺寸、动画、碰撞体）也等修复后再验。
- **生成段无记录**：罗非鱼从提示词到可用模型的这一段没有留下过程数据，只能按本接入口径重新生成；鲤鱼起按「制作约定」的过程留痕要求记录。
