# linyaps init 阶段 token 效率优化实施记录

> 记录本改进方案的**实施结果**，供后续会话/维护者回溯。源分析见 `examples/2026-09-15_linyaps-binary-init-token-risk-nodes.md`。

## 背景

异常 token 消耗主战场在 **init 阶段**（会话启动 → A1 输入解析 → A2 工程树生成 → A3 资源收集 → A4 结构验证 → compat 预检），根因是 agent 行为：整卷读工程树、整卷读 Multica issue JSON、整卷读脚手架脚本、全量枚举 files_res、validate 二次整卷走查。运行时 build/apt 输出洪泛（I-6）已被 compat 路径重定向，分析降级为防回归（保留 `set -x`）。

本批改动以**规范/指令级编辑**收敛 agent 的 init 读取行为：只读目录 listing + 关键文件 + 字段级 JSON + 计数字段，不再整卷拉入 1127 行 `pak_linyaps.sh`、42–64k issue JSON、files_res 全路径枚举；直接跑构建时输出进 log。不引入任何新脚本/新函数——等价实现（`read` 目录级、字段级 selector、`grep`、`run_tasks.sh` 重定向）均已存在。

## 改动清单

| 文件 | 锚点 | 新增 Token 规范 | 对应步骤 |
|------|------|----------------|---------|
| `for-multica/agent.md` | 「运行时路径规则」后 | 新增 `### Token 高效讀取規範（強制）` 节（5 条） | Step 1 |
| `for-multica/agent.md` | Step A2 输出 | 追加「禁止整卷 read 工程树」行 | Step 2 |
| `for-multica/agent.md` | Step A3 输出 | 改为「files_res 計數摘要 + listing」 | Step 3 |
| `for-multica/agent.md` | Step A4 输出 | 改为「複用 A2 快照（`--json` 报告）」 | Step 4 |
| `skills/bin2linyaps.deb.analyze/SKILL.md` | 「## 后续步骤」前 | 新增 `## ⚠️ 上下文效率`（只读计数字段） | Step 5 |
| `skills/bin2linyaps.deb.project-gen/SKILL.md` | 「## 批量初始化」末 | 追加整卷读禁令 + init 不读 `pak_linyaps.sh` 正文 | Step 6 |
| `skills/bin2linyaps.deb.collect-resources/SKILL.md` | 「## 输出数据结构」后 | 追加计数摘要提示（不 append 完整路径） | Step 7 |
| `skills/bin2linyaps.validate-structure/SKILL.md` | 「### 在 Agent 中调用」节 | 追加 `--json` + 禁止全量走查 | Step 8 |
| `skills/bin2linyaps.external-missing-deps-fetch/SKILL.md` | 「## 功能说明」末 | 追加 init 不读 `download_missing_deps.sh` 正文 | Step 9 |

**运行时处理**（未改动）：
- `templates/pak_linyaps.sh` L3 `set -x` **保持不变**（I-6 降级为防回归）
- `skills/bin2linyaps.compat-testing/scripts/run_tasks.sh` step3 已 `> "$log_file" 2>&1`，无需重复

> 注：init agent 不执行 `pak_linyaps.sh` / `ll-builder build`；构建输出重定向属构建阶段（build agent / compat 路径），不在 init agent 规范内。

## 行为约定

**Token 高效讀取規範（agent 编排，强制）**：
1. 工程目录只读清单/关键文件，禁止整卷 read：只读 `linglong.yaml` + `scripts/` 目录 listing；`pak_linyaps.sh` 只 `grep '^ll_id=\|^binary_name='` 确认注入
2. Multica issue JSON 字段级提取（`?field`），只取 `package_id`/`src_url`/`arch`/`orig_version`/`base/runtime`/`whitelist`
3. files_res 以计数摘要呈现（desktop/icons/appdata/mime 数量 + 目标目录 listing），无资源包直接空树
4. 结构验证复用 A2 快照（`validate_project_structure.sh --json`），不重建全量走查
5. init 阶段不读辅助脚本正文（`download_missing_deps.sh`/`handle_special_paths.sh` 仅 `cp` 记录路径；构建执行由 build agent 负责，不在 init agent 范围）

**各 SKILL「上下文效率」提示（持久约束）**：analyze 只读计数字段；project-gen 禁止整卷 read 工程树；collect-resources 只记录 `collected` 计数；validate-structure 带 `--json` 且禁止全量走查；external-missing-deps-fetch init 不读静态脚本正文。

编辑均为**新增**指令/说明，不删除既有功能约束（如「禁止简化脚本」「模板完整复制」），冲突时以既有功能约束为准。

## 验证

- `grep 'Token 高效讀取規範' for-multica/agent.md` → 标题 1 处 + A2/A3/A4 引用；A2/A3/A4 步含「禁止整卷 read 工程树」「計數摘要」「複用 A2 快照」字样
- 5 个 SKILL.md 各 `grep '上下文效率'` → 各 1 处
- `grep -n 'set -x' skills/bin2linyaps.deb.project-gen/templates/pak_linyaps.sh` → L3 存在（未改）
- `grep -n '> "\$log_file" 2>&1' skills/bin2linyaps.compat-testing/scripts/run_tasks.sh` → L234 存在（未改）
- 回归：`bash skills/bin2linyaps.validate-structure/tests/test_validate_project_structure.sh` → **4 PASS / 2 FAIL**。两处失败均为**先存在、与本批改动无关**（本批仅在该 skill 加提示，`git status` 确认脚本 `/scripts/validate_project_structure.sh`、`default_check_config.json` 未改动）：test4 `--help` 因脚本不把 `--help` 当 flag（当作 PROJECT_DIR → exit 1）；test6 空目录因 config 检查类型不匹配（60+ `未知检查类型` 告警后 exit 0 = 通过）。另有 test5/7/9 因 `example/CI_ll_com.opera.browser` fixture 缺失而 skip。

**真实 token 节约无法由本批改动自身断言**：需在后续 agent 会话中对比实测（整卷读 vs 字段级/listing 读的输入 token 量）。上述静态核对（grep + 回归测试）即本批可执行证明。
