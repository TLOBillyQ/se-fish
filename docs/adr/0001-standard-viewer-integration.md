# 0001 Direct standard viewer integration

**Status**: accepted

se-fish 直接接入最新标准 uml-viewer，取消全部五个私有补丁（installer、viewer-seam、restart-spec、companion、restart）。所需能力上游化到 uml-viewer（quality dispatch 配置、companion 失败语义、session 恢复缺口）后，通过版本控制的 `uml-quality.json` 声明 quality 命令映射，由 install.ps1 固定 SHA 接入 Herdr 后端。

备选方案（拒绝）：继续维护项目补丁集——升级时逐文件匹配与冲突处理成本高，且阻碍标准安装流程验收。

后果：图配置保留（policy.edn 三端、输出 `docs/uml/se-fish.edn`）；policy/proposal、session、邮件队列与 `.metrics` 数据在迁移时保留；旧 companion 正常关闭后归档 ownership，再 fresh 创建 Herdr。
