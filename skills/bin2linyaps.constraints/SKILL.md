---
name: bin2linyaps.constraints
description: >
  【linyaps-app-packaging-script-generator】的单一权威：构建约束 + 运行期操作契约。
  承载本 workflow 全部 skills 共享的构建/校验约束与 agent 运行期操作规则，
  由 agent 在初始化阶段一次性载入，各子 skill 与 agent 按路径引用本 SKILL 而非各自复述。
user-invocable: false
---

# bin2linyaps 通用构建约束

本 SKILL 是全部 `bin2linyaps.*` skills 共享约束的唯一权威。**各子 skill 引用本 SKILL，不再各自复述整段约束叙述。**

## 1. wrapper / command 契约

- `command` 与 desktop `Exec` 由 `pak_linyaps.sh` 构建时通过 **wrapper 机制** 自动设置（提取 binary_name → 生成 `bin/<name>.wrapper` → 回填 `command` 与 `Exec=`）。
- **禁止** 手动设置 `linglong.yaml` 的 `command` 字段；模板中 `command: ""` 是正确的。
- **禁止** 在 `pak_linyaps.sh` 的 envsubst 阶段导出或填充 `command` 变量。
- **禁止** 在资源收集阶段修改 desktop 文件的 Exec 字段；只修复 Icon 路径。

## 2. version 契约

- `version` 与 `package.version` **必须保持** `${ll_version}` 变量，**禁止绝对化**（如 `version: "1.0"`）。
- 版本由 `convert_version_to_linglong()`（`deb_to_linglong.py`）自动归一化。
- version 的替换**只能**由 `pak_linyaps.sh` 在构建时通过 envsubst 完成。
- 若误将 version 绝对化，`validate_linglong_yaml.py` 会输出可执行的 `sed` 恢复命令。

## 3. package_id 契约

- 工程目录命名：`CI_ll_<package_id>`。
- `package_id` 遵循反向域名格式（`com.example.app`）。
- `ll_id` 必须非空。

## 4. base / runtime 契约

- base/runtime 组合必须通过 `config/base_runtime_whitelist.conf` 白名单校验。
- 默认值：`org.deepin.base/25.2.2`、`org.deepin.runtime.dtk/25.2.2`（可被 `agent-config.json` 覆盖）。

## 5. 依赖存在性核验

- 写入 `buildext.apt.depends` 的依赖（含 deb `Depends` 解析、`missing_deps` 的 `apt-file` 结果）必须逐包 `apt-cache show` 核验（stdout 出现 `Package:`）通过。
- 由 `bin2linyaps.deb.analyze` 的 `scripts/depends.py` 统一执行；agent 在生成前兜底调用。

## 6. 模板完整性

- `pak_linyaps.sh` 必须从模板**完整复制**，不得删除函数或脚本调用、不得简化 wrapper 生成逻辑。
- 模板路径：`linglong.yaml` 源使用 `templates/linglong.yaml`，`files_res` 源使用 `templates/files_res`。

## 7. 运行期操作契约
- 入口必须解析并校验绝对 WORKSPACE_ROOT、agent_config_path、skills_root；output_dir/data_dir 使用已解析配置值；运行时禁止 ${tag} 或依赖日期生成的路径。
- skills 固定位于 WORKSPACE_ROOT/skills/<name>/SKILL.md，无需搜索；禁止把仓库内 skill 当作可按名称解析的具名工具调用（运行时未注册，会报 "Tool skill not found"）。
- 本 SKILL 为纯指引（无脚本）：agent 初始化读一次，后续按路径引用，不在各步骤重复展开。
- 脚本调用使用相对 WORKSPACE_ROOT 或绝对路径，禁止 cd 切换工作目录后再执行。
