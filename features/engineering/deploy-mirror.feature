# language: zh-CN
# 场景清单：
#   部署镜像 1: 部署把仓库根各端镜像到工作区根
#   部署镜像 2: 部署不触碰工作区中不归本仓库的文件
#   部署镜像 3: 仓库根白名单之外的内容不进工作区
#
# 工程 feature：背景在 ./tmp 下创建临时工作区，不启动对局。规则真源 CONTEXT.md「部署树」。
# 规则：
#   - 部署（lua tools/cli.lua deploy，工作区由 EGGY_WORKSPACE 指定）把仓库根白名单 <端>/（client/
#     common/ server/）下每个文件落到工作区 /<端>/ 同相对路径；仓库根其余内容不部署。
#   - 部署只重置本仓库拥有的白名单子树；工作区里 server.TableMgr、unit_scripts、data、eggy.json
#     等不归本仓库的内容，以及编辑器自己生成的 .gm/，一律原样保留。
#   - 路径列表为空格分隔；「存在文件」要求列表里每个路径都存在，「预置文件」逐个创建。
#   - 场景 2 的预置与保留分成两列（值相同）：同一列既预置又断言的话，改一个路径会把两边
#     一起改掉，断言恒真、变异体必然存活。分列后动任一侧都会让断言落空。
#   - 临时工作区不是编辑器绑定的工程（场景 2 预置的 eggy.json 是伪造的绑定），部署步骤把
#     USERPROFILE 指到空的临时 home，编辑器收尾按「找不到 editor-cli.exe」跳过：本车道
#     只验磁盘镜像语义，带编辑器的收尾在真机上跑。
# 执行成本：验收运行时对每个例子行都重跑一遍背景与全部步骤，而一次部署是整树镜像。
#   所以待验路径走一个空格分隔的列表参数、每个场景只留一行例子：一个场景一次部署，
#   而不是一行一次。
功能: 部署镜像

背景:
  假如 一个空的临时工作区

场景大纲: 部署镜像 1: 部署把仓库根各端镜像到工作区根
  当 执行部署到临时工作区
  那么 临时工作区存在文件<路径列表>

  例子:
  | 路径列表                                                                                                                     |
  | server/main.lua server/Mgr/MgrFish.lua server/Mgr/MgrAbility.lua server/_trigger/GlobalVars.lua server/packages/ability_system/api.lua client/main.lua client/ScreenHandlers/ScreenFishing.lua common/GameCfg.lua common/Util.lua |

场景大纲: 部署镜像 2: 部署不触碰工作区中不归本仓库的文件
  假如 临时工作区预置文件<预置列表>
  当 执行部署到临时工作区
  那么 临时工作区存在文件<保留列表>

例子:
  | 预置列表                                                                                                                       | 保留列表                                                                                                                       |
  | eggy.json EggyAPI.lua EggyEditorAPI.lua data/FontData.lua unit_scripts/generated.lua client/host_only/keep.lua .gm/probe.lua | eggy.json EggyAPI.lua EggyEditorAPI.lua data/FontData.lua unit_scripts/generated.lua client/host_only/keep.lua .gm/probe.lua |

场景: 部署镜像 3: 仓库根白名单之外的内容不进工作区
  当 执行部署到临时工作区
  那么 部署白名单为client common server
  并且 临时工作区不存在目录tools
